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
import "../core/interface/IProtocolPosition.sol";
import "hardhat/console.sol";

contract UniV3Manager is ReentrancyGuard, IProtocolPosition, IUniswapV3MintCallback {

    using SafeERC20 for IERC20;
    IERC20 immutable token0;
    IERC20 immutable token1;
    IUniswapV3Factory private immutable uniFactory;
    ISwapRouter private immutable swapRouter;
    IUniswapV3Pool v3Pool;
    bool minting;

    uint256 private constant FixedPoint128_Q128 = 0x100000000000000000000000000000000;

    mapping(address => uint256) public nextId;

    // user address => positionIds
    mapping(address => bytes32[]) public positionIds;

    // positionKey => ComposedLiquidity
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
        uint128 liquidity;
    }

    modifier verifyPositionExists(address _account, bytes32 _positionKey) {

        require(liquidities[_positionKey].account == _account, "Position does not exist for the given account");
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

    function convertBytes32ToOpenPositionArgs(bytes32[] memory _args) internal returns (UniV3OpenArgs memory) {

        require(_args.length == 6, "Invalid number of arguments");
        
        return UniV3OpenArgs({
            tickLower: int24(uint24(uint256(_args[0]))),
            tickUpper: int24(uint24(uint256(_args[1]))),
            feeTier: uint24(uint256(_args[2])),
            amount0Desired: uint256(_args[3]),
            amount1Desired: uint256(_args[4]),
            liquidityDesired: uint128(uint256(_args[5])) 
        });
    }

    function openPosition(address _account, bytes32[] calldata _args) external payable override returns (bytes32[] memory) {

        UniV3OpenArgs memory uniV3Args = convertBytes32ToOpenPositionArgs(_args);

        v3Pool = IUniswapV3Pool(
                    uniFactory.getPool(
                        address(token0),
                        address(token1),
                        uniV3Args.feeTier
                    ));
        console.log('v3Pool:', address(v3Pool));
        console.log('uniV3Args.liquidityDesired:', uniV3Args.liquidityDesired);
        console.log('amount0:', uniV3Args.amount0Desired);
        console.log('amount1:', uniV3Args.amount1Desired);
        
        (uint160 sqrtPriceX96, , , , , , ) = v3Pool.slot0();
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(uniV3Args.tickLower),
                TickMath.getSqrtRatioAtTick(uniV3Args.tickUpper),
                uniV3Args.amount0Desired,
                uniV3Args.amount1Desired
            );

        console.log('liquidity:', liquidity);
        console.log('sqrtPriceX96:', sqrtPriceX96);
        minting = true;
        (uint256 amount0Minted, uint256 amount1Minted) = v3Pool.mint(address(this), uniV3Args.tickLower, uniV3Args.tickUpper, liquidity, abi.encode(address(this)));

        console.log('amount0:', uniV3Args.amount0Desired);
        console.log('amount1:', uniV3Args.amount1Desired);
        console.log('amount0Minted:', amount0Minted);
        console.log('amount1Minted:', amount1Minted);
        console.log('_account:', _account);
        
        uint256 amount0 = uniV3Args.amount0Desired - amount0Minted;
        uint256 amount1 = uniV3Args.amount1Desired - amount1Minted;

        bytes32 positionKey = addPositionInfo(_account, uniV3Args.tickLower, uniV3Args.tickUpper, uniV3Args.feeTier, uniV3Args.liquidityDesired);
        returnFund(_account, amount0, amount1);
        console.logBytes32(positionKey);

        bytes32[] memory result = new bytes32[](6);
        result[0] = positionKey;
        // result[1] = bytes32(0);
        result[2] = bytes32(uint256(uniV3Args.liquidityDesired));
        result[3] = bytes32(amount0);
        result[4] = bytes32(amount1);
        result[5] = bytes32(uint256(uniV3Args.feeTier));

        unCollectedFee(positionKey);

        return result;
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

        require(msg.sender == address(v3Pool));
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
        uint128 _liquidity
    )
        private
        returns (bytes32 positionKey)
    {
        UniV3Position memory uniV3Position;
        uniV3Position.account = _account;
        uniV3Position.tickLower = _tickLower;
        uniV3Position.tickUpper = _tickUpper;
        uniV3Position.feeTier = _feeTier;
        uniV3Position.liquidity = _liquidity;

        nextId[_account]++;
        positionKey = getKey(_account, _tickLower, _tickUpper);

        positionIds[_account].push(positionKey);
        liquidities[positionKey] = uniV3Position;
    }

    function computeUncollectedFee(uint128 accountLiquidity, int24 tickLower, int24 tickUpper)
        internal
        view
        returns (
            uint128 fee0,
            uint128 fee1
        )
    {   
        uint128 liquidity;
        bytes32 positionKey = keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
        (liquidity, , , fee0, fee1) = v3Pool.positions(positionKey);

        fee0 = uint128(FullMath.mulDiv(fee0, accountLiquidity, liquidity));
        fee1 = uint128(FullMath.mulDiv(fee1, accountLiquidity, liquidity));

        console.log('calculated fee...................');
        console.log('liquidity:', liquidity);
        console.log('fee0:', fee0);
        console.log('fee1:', fee1);
    }

    function getKey(address _addr, int24 _tickLower, int24 _tickUpper) private view
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_addr, nextId[_addr], _tickLower, _tickUpper));
    }

    function closePosition(address _account, bytes32[] calldata _args) 
        external payable override 
        returns (bytes32[] memory, Fund[] memory) 
    {
        // Parse input arguments from the bytes32 array
        bytes32 _positionKey = _args[0];

        // Verify position exists (assuming the modifier was a function)
        require(liquidities[_positionKey].account == _account, "Position does not exist");
        
        (uint128 fee0, uint128 fee1) = unCollectedFee(_positionKey);

        UniV3Position memory userLiquidity = positionOf(_positionKey);
        (uint256 owed0, uint256 owed1) = v3Pool.burn(userLiquidity.tickLower, userLiquidity.tickUpper, userLiquidity.liquidity);
        (uint256 amount0, uint256 amount1) = v3Pool.collect(address(this), userLiquidity.tickLower, userLiquidity.tickUpper, uint128(owed0 + fee0), uint128(owed1 + fee1));

        removePositionKey(_account, _positionKey);

        IProtocolPosition.Fund[] memory returnedFund = new IProtocolPosition.Fund[](2); 

        returnedFund[0].token = address(token0);
        returnedFund[1].token = address(token1);

        returnedFund[0].amount = amount0;
        returnedFund[1].amount = amount1;

        // returnFund(_account, collect0, collect1);

        bytes32[] memory result = new bytes32[](0);
        // result[0] = bytes32(collect0);
        // result[1] = bytes32(collect1);

        return (result, returnedFund);
    }
    
    function removePositionKey(address _account, bytes32 _positionKey) 
        internal 
    {
        for (uint256 i = 0; i < positionIds[_account].length; i++) {
            if (positionIds[_account][i] == _positionKey) {
                // Replace the element with the last element in the array and remove the last element
                positionIds[_account][i] = positionIds[_account][positionIds[_account].length - 1];
                positionIds[_account].pop();

                // Remove the ComposedLiquidity from the mapping
                delete liquidities[_positionKey];

                // The element has been removed, no need to continue the loop
                return;
            }
        }
    }

    /// @notice Collects the fees associated with provided liquidity
    /// @dev The contract must hold the erc721 token before it can collect fees
    /// @param _tokenId The id of the erc721 token
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collectAllFees(
        address _recipient, 
        bytes32 _positionKey, 
        uint256 _tokenId
        ) 
        external 
        returns (uint256 amount0, uint256 amount1) 
    {
        (uint128 fee0, uint128 fee1) = unCollectedFee(_positionKey);
        if (fee0 > 0 || fee1 > 0) {
            UniV3Position memory userLiquidity = positionOf(_positionKey);
            (amount0, amount1) = v3Pool.collect(address(this), userLiquidity.tickLower, userLiquidity.tickUpper, fee0, fee1);
        }
    }

    function unCollectedFee(bytes32 _positionKey) 
        public 
        view 
        returns (uint128 fee0, uint128 fee1) 
    {
        UniV3Position memory userLiquidity = positionOf(_positionKey);
        (fee0, fee1) = computeUncollectedFee(userLiquidity.liquidity, userLiquidity.tickLower, userLiquidity.tickUpper);

        console.log("unCollectedFee.....");
        console.log("fee0: ", fee0);
        console.log("fee1: ", fee1);
    }

    function receiveFund(address _fundingAcc, Fund[] memory _fund) external {
        
        for (uint i = 0; i < _fund.length; i++) {
            IERC20(_fund[i].token).safeTransferFrom(_fundingAcc, address(this), _fund[i].amount);
        }
    }

    function returnFund(address _fundingAcc, Fund[] memory _fund) external {
        
        for (uint i = 0; i < _fund.length; i++) {
            IERC20(_fund[i].token).safeTransfer(_fundingAcc, _fund[i].amount);
        }
    }

    function returnFund(address _account, uint256 _amount0, uint256 _amount1) 
        internal 
    {
        token0.safeTransfer(_account, _amount0);
        token1.safeTransfer(_account, _amount1);
    }
}