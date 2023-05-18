// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import { TickMath } from "@arrakisfi/v3-lib-0.8/contracts/TickMath.sol";
import { FullMath, LiquidityAmounts } from "@arrakisfi/v3-lib-0.8/contracts/LiquidityAmounts.sol";
import "../core/interface/IProtocolPositionManager.sol";
import "hardhat/console.sol";

contract UniV3Manager is ReentrancyGuard, IProtocolPositionManager, IUniswapV3MintCallback {

    using SafeERC20 for IERC20;
    IERC20 immutable token0;
    IERC20 immutable token1;
    IUniswapV3Factory private immutable uniFactory;
    ISwapRouter private immutable swapRouter;
    bool minting;
    IUniswapV3Pool pool;

    uint256 private constant FixedPoint128_Q128 = 0x100000000000000000000000000000000;

    mapping(address => uint256) public nextId;

    // user address => positionIds
    mapping(address => bytes32[]) public positionIds;

    // key => ComposedLiquidity
    mapping(bytes32 => UniV3Position) liquidities;

    struct UniV3OpenArgs {
        int24 tickLower;
        int24 tickUpper;
        uint24 feeTier;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint128 liquidityDesired;
    }

    struct UniV3Position {
        address account;
        int24 tickLower;
        int24 tickUpper;
        uint24 feeTier;
        IUniswapV3Pool pool;
        uint128 liquidity;
        uint160 entryPriice;
        FeeGrowthData feeGrowthData;
    }

    struct FeeGrowthData {
        uint256 feeGrowthInside0X128;
        uint256 feeGrowthInside1X128;
    }

    modifier verifyPositionExists(address _account, bytes32 _key) {

        require(liquidities[_key].account == _account, "Position does not exist for the given account");
        _;
    }

    constructor (
        IUniswapV3Factory _uniFactory, 
        ISwapRouter _swapRouter,
        address _token0,
        address _token1
        ) 
    {
        uniFactory = _uniFactory;
        swapRouter = _swapRouter;

        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    function positionOf(bytes32 _positionId)
        public view
        returns (UniV3Position memory)
    {
        return liquidities[_positionId];
    }

    function convertToOpenOpenArgs(bytes memory _args) 
        internal pure 
        returns (UniV3OpenArgs memory) 
    {
        (   int24 tickLower, 
            int24 tickUpper,
            uint24 feeTier, 
            uint256 amount0Desired, 
            uint256 amount1Desired, 
            uint128 liquidityDesired
        ) = abi.decode(_args, (int24, int24, uint24, uint256, uint256, uint128));
        
        return UniV3OpenArgs({
            tickLower: tickLower,
            tickUpper: tickUpper,
            feeTier: feeTier,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            liquidityDesired: liquidityDesired
        });
    }

    function openPosition(address _account, bytes calldata _args) 
        external payable override 
        returns (bytes32 key_, bytes memory result_) 
    {
        UniV3OpenArgs memory openArgs = convertToOpenOpenArgs(_args);
        require(openArgs.liquidityDesired > 0, "liquidity = 0");

        pool = IUniswapV3Pool(
                    uniFactory.getPool(
                        address(token0),
                        address(token1),
                        openArgs.feeTier
                    ));
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        minting = true;
        (uint256 amount0Minted, uint256 amount1Minted) = pool.mint(address(this), openArgs.tickLower, openArgs.tickUpper, openArgs.liquidityDesired, abi.encode(address(this)));

        console.log('v3Pool:', address(pool));
        console.log('liquidityDesired:', openArgs.liquidityDesired);
        console.log('amount0:', openArgs.amount0Desired);
        console.log('amount1:', openArgs.amount1Desired);
        console.log('amount0Minted:', amount0Minted);
        console.log('amount1Minted:', amount1Minted);
        console.log('_account:', _account);
        
        uint256 amount0 = openArgs.amount0Desired - amount0Minted;
        uint256 amount1 = openArgs.amount1Desired - amount1Minted;

        key_ = addPositionInfo(_account, openArgs.tickLower, openArgs.tickUpper, openArgs.feeTier, pool, openArgs.liquidityDesired, sqrtPriceX96);
        returnFund(_account, constructFund(amount0, amount1));

        result_ = abi.encode(
            openArgs.liquidityDesired,
            token0,
            token1,
            openArgs.feeTier
        );
    }

    /// @notice Callback function of uniswapV3Pool mint
    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        console.log('uniswapV3MintCallback...............');
        console.log('amount0:', amount0);
        console.log('amount1:', amount1);

        require(msg.sender == address(pool));
        require(minting == true);
        minting = false;

        if (amount0 > 0) token0.safeTransfer(msg.sender, amount0);
        if (amount1 > 0) token1.safeTransfer(msg.sender, amount1);
    }

    function addPositionInfo(
        address _account,
        int24 _tickLower, 
        int24 _tickUpper,
        uint24 _feeTier,
        IUniswapV3Pool _pool,
        uint128 _liquidity,
        uint160 _entryPriice
    )
        private
        returns (bytes32 key)
    {
        UniV3Position memory uniV3Position;
        uniV3Position.account = _account;
        uniV3Position.tickLower = _tickLower;
        uniV3Position.tickUpper = _tickUpper;
        uniV3Position.feeTier = _feeTier;
        uniV3Position.pool = _pool;
        uniV3Position.liquidity = _liquidity;
        uniV3Position.entryPriice = _entryPriice;

        nextId[_account]++;
        key = keccak256(abi.encodePacked(_account, nextId[_account], _tickLower, _tickUpper));

        positionIds[_account].push(key);
        liquidities[key] = uniV3Position;

        updateUniPosition(key);
    }

    function updateUniPosition(bytes32 _key) 
        private 
    {
        UniV3Position storage accountLiquidity = liquidities[_key];
        bytes32 uniKey = keccak256(abi.encodePacked(address(this), accountLiquidity.tickLower, accountLiquidity.tickUpper));
        (
            ,
            ,
            ,
            accountLiquidity.feeGrowthData.feeGrowthInside0X128,
            accountLiquidity.feeGrowthData.feeGrowthInside1X128
        ) =
            IUniswapV3Pool(uniFactory.getPool(address(token0), address(token1), accountLiquidity.feeTier)).positions(uniKey);

        (
            accountLiquidity.feeGrowthData.feeGrowthInside0X128, 
            accountLiquidity.feeGrowthData.feeGrowthInside1X128
        ) =
            getFeeGrowthInside(accountLiquidity.tickLower, accountLiquidity.tickUpper, accountLiquidity.pool);
    }

    function closePosition(address _account, bytes calldata _args) 
        external payable override 
        returns (bytes memory, Fund[] memory) 
    {
        // Parse input arguments from the bytes32 array
        bytes32 _key = bytes32(_args); 

        // Verify position exists (assuming the modifier was a function)
        require(liquidities[_key].account == _account, "Position does not exist");
        
        UniV3Position memory accountLiquidity = positionOf(_key);

        (uint128 fee0, uint128 fee1) = unCollectedFee(_key);
        (uint256 owed0, uint256 owed1) = accountLiquidity.pool.burn(accountLiquidity.tickLower, accountLiquidity.tickUpper, accountLiquidity.liquidity);
        (uint256 amount0, uint256 amount1) = accountLiquidity.pool.collect(address(this), accountLiquidity.tickLower, accountLiquidity.tickUpper, uint128(owed0 + fee0), uint128(owed1 + fee1));

        removeKey(_account, _key);

        IProtocolPositionManager.Fund[] memory returnedFund = new IProtocolPositionManager.Fund[](2); 

        returnedFund[0].token = address(token0);
        returnedFund[1].token = address(token1);

        returnedFund[0].amount = amount0;
        returnedFund[1].amount = amount1;

        bytes memory result = abi.encode(new bytes32[](0));
        return (result, returnedFund);
    }
    
    function removeKey(address _account, bytes32 _key) 
        internal 
    {
        for (uint256 i = 0; i < positionIds[_account].length; i++) {
            if (positionIds[_account][i] == _key) {
                // Replace the element with the last element in the array and remove the last element
                positionIds[_account][i] = positionIds[_account][positionIds[_account].length - 1];
                positionIds[_account].pop();

                // Remove the ComposedLiquidity from the mapping
                delete liquidities[_key];

                // The element has been removed, no need to continue the loop
                return;
            }
        }
    }

    function unCollectedFee(bytes32 _key) 
        public 
        view 
        returns (uint128 fee0, uint128 fee1) 
    {
        UniV3Position memory accountLiquidity = positionOf(_key);

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
            getFeeGrowthInside(accountLiquidity.tickLower, accountLiquidity.tickUpper, accountLiquidity.pool);

        fee0 = uint128(FullMath.mulDiv(accountLiquidity.liquidity, feeGrowthInside0X128 - accountLiquidity.feeGrowthData.feeGrowthInside0X128, FixedPoint128_Q128));
        fee1 = uint128(FullMath.mulDiv(accountLiquidity.liquidity, feeGrowthInside1X128 - accountLiquidity.feeGrowthData.feeGrowthInside1X128, FixedPoint128_Q128));
    }

    function getFeeGrowthInside(
        int24 tickLower,
        int24 tickUpper,
        IUniswapV3Pool pool
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        
        (, int24 tickCurrent, , , , , ) = pool.slot0();

        uint256 feeGrowthGlobal0X128 = pool.feeGrowthGlobal0X128();
        uint256 feeGrowthGlobal1X128 = pool.feeGrowthGlobal1X128();

        (, , uint256 feeGrowthOutside0Lower, uint256 feeGrowthOutside1Lower, , , ,) = pool.ticks(tickLower);
        (, , uint256 feeGrowthOutside0Upper, uint256 feeGrowthOutside1Upper, , , ,) = pool.ticks(tickUpper);

        // calculate fee growth below
        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;
        if (tickCurrent >= tickLower) {
            feeGrowthBelow0X128 = feeGrowthOutside0Lower;
            feeGrowthBelow1X128 = feeGrowthOutside1Lower;
        } else {
            feeGrowthBelow0X128 = feeGrowthGlobal0X128 - feeGrowthOutside0Lower;
            feeGrowthBelow1X128 = feeGrowthGlobal1X128 - feeGrowthOutside1Lower;
        }

        // calculate fee growth above
        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
        if (tickCurrent < tickUpper) {
            feeGrowthAbove0X128 = feeGrowthOutside0Upper;
            feeGrowthAbove1X128 = feeGrowthOutside1Upper;
        } else {
            feeGrowthAbove0X128 = feeGrowthGlobal0X128 - feeGrowthOutside0Upper;
            feeGrowthAbove1X128 = feeGrowthGlobal1X128 - feeGrowthOutside1Upper;
        }

        feeGrowthInside0X128 = feeGrowthGlobal0X128 + feeGrowthBelow0X128 - feeGrowthAbove0X128;
        feeGrowthInside1X128 = feeGrowthGlobal1X128 + feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }

    function constructFund(uint256 _amount0, uint256 _amount1) internal view returns (Fund[] memory fund_)
    {
        fund_ = new Fund[](2);

        fund_[0].token = address(token0);
        fund_[1].token = address(token1);

        fund_[0].amount = _amount0;
        fund_[1].amount = _amount1;
    }

    function feesOf(bytes32 _key) external view returns (Fund[] memory) 
    {
        (uint128 fee0, uint128 fee1) = unCollectedFee(_key);
        return constructFund(fee0, fee1);
    }

    function infoOf(bytes32 _key) external view override returns (bytes memory info_) {
    }

    function claimFees(address _account, bytes32 _key) 
        external 
    {
        console.log('collectAllFees...............');
        (uint128 fee0, uint128 fee1) = unCollectedFee(_key);
        if (fee0 > 0 || fee1 > 0) {
            UniV3Position memory accountLiquidity = positionOf(_key);

            accountLiquidity.pool.burn(accountLiquidity.tickLower, accountLiquidity.tickUpper, 0);
            (uint128 amount0, uint128 amount1) = accountLiquidity.pool.collect(address(this), accountLiquidity.tickLower, accountLiquidity.tickUpper, fee0, fee1);

            console.log('fee0:', fee0);
            console.log('fee1:', fee1);
            console.log('amount0:', amount0);
            console.log('amount1:', amount1);
            
            updateUniPosition(_key);
            returnFund(_account, constructFund(amount0, amount1));
        }
    }

    function receiveFund(address _account, Fund[] memory _fund) external 
    {
        for (uint i = 0; i < _fund.length; i++) {
            IERC20(_fund[i].token).safeTransferFrom(_account, address(this), _fund[i].amount);
        }
    }

    function returnFund(address _account, Fund[] memory _fund) public 
    {
        for (uint i = 0; i < _fund.length; i++) {
            IERC20(_fund[i].token).safeTransfer(_account, _fund[i].amount);
        }
    }
}