// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import "../interface/uniswap/INonfungiblePositionManager.sol";
import { TickMath } from "@arrakisfi/v3-lib-0.8/contracts/TickMath.sol";
import { FullMath } from "@arrakisfi/v3-lib-0.8/contracts/LiquidityAmounts.sol";
import "../core/interface/IProtocolPosition.sol";
import "hardhat/console.sol";

contract UniV3Vault is ReentrancyGuard, IProtocolPosition {

    using SafeERC20 for IERC20;
    IERC20 immutable token0;
    IERC20 immutable token1;
    IUniswapV3Factory private immutable uniFactory;
    INonfungiblePositionManager private immutable positionManager;
    ISwapRouter private immutable swapRouter;

    uint256 private constant FixedPoint128_Q128 = 0x100000000000000000000000000000000;

    mapping(address => uint256) public nextId;

    // user address => positionIds
    mapping(address => bytes32[]) public positionIds;

    // positionKey => ComposedLiquidity
    mapping(bytes32 => UniV3Position) liquidities;

    struct UniV3OpenArgvs {
        int24 tickLower;
        int24 tickUpper;
        uint24 feeTier;
        uint256 amount0;
        uint256 amount1;
    }

    struct UniV3Position {
        address account;
        int24 tickLower;
        int24 tickUpper;
        uint24 feeTier;
        uint128 liquidity;
        uint256 tokenId;
        FeeGrowthData feeGrowthData;
    }

    struct FeeGrowthData {
        uint256 feeGrowthInside0X128;
        uint256 feeGrowthInside1X128;
        uint256 feeGrowthLast0X128;
        uint256 feeGrowthLast1X128;
    }

    modifier verifyPositionExists(address _account, bytes32 _positionKey) {

        require(liquidities[_positionKey].account == _account, "Position does not exist for the given account");
        _;
    }

    constructor (
        IUniswapV3Factory _uniFactory, 
        ISwapRouter _swapRouter,
        INonfungiblePositionManager _positionManager,
        address _token0,
        address _token1
        ) 
    {
        uniFactory = _uniFactory;
        swapRouter = _swapRouter;
        positionManager = _positionManager;

        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    function positionOf(bytes32 _positionId)
        public view
        returns (UniV3Position memory)
    {
        return liquidities[_positionId];
    }

    function convertBytes32ToOpenPositionArgs(bytes32[] memory _args) internal returns (UniV3OpenArgvs memory) {

        require(_args.length == 5, "Invalid number of arguments");
        
        return UniV3OpenArgvs({
            tickLower: int24(uint24(uint256(_args[0]))),
            tickUpper: int24(uint24(uint256(_args[1]))),
            feeTier: uint24(uint256(_args[2])),
            amount0: uint256(_args[3]),
            amount1: uint256(_args[4])
        });
    }

    function openPosition(address _account, bytes32[] calldata _args) external payable override returns (bytes32[] memory) {

        UniV3OpenArgvs memory uniV3Args = convertBytes32ToOpenPositionArgs(_args);

        

        // Approve the Uniswap V3 contract to spend the tokens on behalf of this contract
        token0.approve(address(positionManager), uniV3Args.amount0);
        token1.approve(address(positionManager), uniV3Args.amount1);

        // Mint the position
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: uniV3Args.feeTier,
            tickLower: uniV3Args.tickLower,
            tickUpper: uniV3Args.tickUpper,
            amount0Desired: uniV3Args.amount0,
            amount1Desired: uniV3Args.amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0Minted,
            uint256 amount1Minted
        ) = positionManager.mint(params);

        console.log('amount0:', uniV3Args.amount0);
        console.log('amount1:', uniV3Args.amount1);
        console.log('amount0Minted:', amount0Minted);
        console.log('amount1Minted:', amount1Minted);
        console.log('_account:', _account);
        
        uint256 amount0 = uniV3Args.amount0 - amount0Minted;
        uint256 amount1 = uniV3Args.amount1 - amount1Minted;

        bytes32 positionKey = addPositionInfo(_account, uniV3Args.tickLower, uniV3Args.tickUpper, uniV3Args.feeTier, tokenId, liquidity);
        returnFund(_account, amount0, amount1);
        console.logBytes32(positionKey);

        bytes32[] memory result = new bytes32[](6);
        result[0] = positionKey;
        result[1] = bytes32(tokenId);
        result[2] = bytes32(uint256(liquidity));
        result[3] = bytes32(amount0);
        result[4] = bytes32(amount1);
        result[5] = bytes32(uint256(uniV3Args.feeTier));

        return result;
    }

    function addPositionInfo(
        address _account,
        int24 _tickLower, 
        int24 _tickUpper,
        uint24 _feeTier,
        uint256 _tokenId,
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
        uniV3Position.tokenId = _tokenId;
        uniV3Position.liquidity = _liquidity;

        nextId[_account]++;
        positionKey = getKey(_account, _tickLower, _tickUpper);

        positionIds[_account].push(positionKey);
        liquidities[positionKey] = uniV3Position;

        updateUniPosition(positionKey);
    }

    function getKey(address _addr, int24 _tickLower, int24 _tickUpper) private view
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_addr, nextId[_addr], _tickLower, _tickUpper));
    }

    function closePosition(address _account, bytes32[] calldata _args) external payable override returns (bytes32[] memory) {
        // Parse input arguments from the bytes32 array
        bytes32 _positionKey = _args[0];

        // Verify position exists (assuming the modifier was a function)
        require(liquidities[_positionKey].account == _account, "Position does not exist");

        UniV3Position memory userLiquidity = positionOf(_positionKey);

        // Decrease liquidity to zero
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: userLiquidity.tokenId,
            liquidity: userLiquidity.liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });
        (uint256 burn0, uint256 burn1) = positionManager.decreaseLiquidity(decreaseLiquidityParams);

        // Remove liquidity and collect fees
        (uint256 fee0, uint256 fee1) = unCollectedFee(_positionKey);
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: userLiquidity.tokenId,
            recipient: address(this),
            amount0Max: uint128(burn0 + fee0),
            amount1Max: uint128(burn1 + fee1)
        });
        (uint256 collect0, uint256 collect1) = positionManager.collect(collectParams);

        updateUniPosition(_positionKey);
        removePositionKey(_account, _positionKey);

        returnFund(_account, collect0, collect1);

        bytes32[] memory result = new bytes32[](2);
        result[0] = bytes32(collect0);
        result[1] = bytes32(collect1);

        return result;
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

    function updateUniPosition(bytes32 _positionKey) private {

        UniV3Position storage userLiquidity = liquidities[_positionKey];
        bytes32 uniKey = keccak256(abi.encodePacked(address(this), userLiquidity.tickLower, userLiquidity.tickUpper));
        (
            ,
            ,
            ,
            userLiquidity.feeGrowthData.feeGrowthInside0X128,
            userLiquidity.feeGrowthData.feeGrowthInside1X128
        ) =
            IUniswapV3Pool(uniFactory.getPool(address(token0), address(token1), userLiquidity.feeTier)).positions(uniKey);

        (
            userLiquidity.feeGrowthData.feeGrowthLast0X128, 
            userLiquidity.feeGrowthData.feeGrowthLast1X128
        ) = 
            computeFeeGrowth(_positionKey);
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
        (uint256 fee0, uint256 fee1) = unCollectedFee(_positionKey);

        if (fee0 !=0 || fee1 != 0) {
            // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
            INonfungiblePositionManager.CollectParams memory params =
                INonfungiblePositionManager.CollectParams({
                    tokenId: _tokenId,
                    recipient: address(this),
                    amount0Max: uint128(fee0),
                    amount1Max: uint128(fee1)
                });

            (amount0, amount1) = positionManager.collect(params);
            console.log("collectAllFees..");
            console.log("amount0: ", amount0);
            console.log("amount1: ", amount1);

            updateUniPosition(_positionKey);
            returnFund(_recipient, amount0, amount1);
        }
    }

    function unCollectedFee(bytes32 _positionKey) 
        public 
        view 
        returns (uint256 fee0, uint256 fee1) 
    {
        (uint256 feeGrowth0, uint256 feeGrowth1) = computeFeeGrowth(_positionKey);

        UniV3Position memory userLiquidity = positionOf(_positionKey);

        fee0 = feeGrowth0 - userLiquidity.feeGrowthData.feeGrowthLast0X128;
        fee1 = feeGrowth1 - userLiquidity.feeGrowthData.feeGrowthLast1X128;

        console.log("unCollectedFee.....");
        console.log("fee0: ", fee0);
        console.log("fee1: ", fee1);
    }

    function computeFeeGrowth(bytes32 _positionKey) 
        public 
        view 
        returns (uint256 fee0, uint256 fee1) 
    {
        (
            IUniswapV3Pool pool,
            int24 tickLower,
            int24 tickUpper,
            int24 tickCurrent,
            ,
            uint256 feeGrowthOutside0Lower,
            uint256 feeGrowthOutside1Lower,
            uint256 feeGrowthOutside0Upper,
            uint256 feeGrowthOutside1Upper
        ) = getUncollectedFeeData(_positionKey);

        UniV3Position memory userLiquidity = positionOf(_positionKey);

        fee0 = computeUncollectedFees(
            pool.feeGrowthGlobal0X128(),
            feeGrowthOutside0Lower,
            feeGrowthOutside0Upper,
            userLiquidity.feeGrowthData.feeGrowthInside0X128,
            tickCurrent,
            tickLower,
            tickUpper,
            userLiquidity.liquidity
        );

        fee1 = computeUncollectedFees(
            pool.feeGrowthGlobal1X128(),
            feeGrowthOutside1Lower,
            feeGrowthOutside1Upper,
            userLiquidity.feeGrowthData.feeGrowthInside1X128,
            tickCurrent,
            tickLower,
            tickUpper,
            userLiquidity.liquidity
        );
    }
    
    function getUncollectedFeeData(bytes32 _positionKey) 
        public
        view
        returns (
            IUniswapV3Pool pool,
            int24 tickLower,
            int24 tickUpper,
            int24 tickCurrent,
            uint256 liquidity,
            uint256 feeGrowthOutside0Lower,
            uint256 feeGrowthOutside1Lower,
            uint256 feeGrowthOutside0Upper,
            uint256 feeGrowthOutside1Upper
        )
    {
        // Get position details
        UniV3Position memory userLiquidity = positionOf(_positionKey);
        
        tickLower = userLiquidity.tickLower;
        tickUpper = userLiquidity.tickUpper;
        liquidity = userLiquidity.liquidity;

        // Calculate uncollected fees
        pool = IUniswapV3Pool(uniFactory.getPool(address(token0), address(token1), userLiquidity.feeTier));

        (, , feeGrowthOutside0Lower, feeGrowthOutside1Lower, , , ,) = pool.ticks(tickLower);
        (, , feeGrowthOutside0Upper, feeGrowthOutside1Upper, , , ,) = pool.ticks(tickUpper);

        (, tickCurrent, , , , , ) = pool.slot0();
    }

    function computeUncollectedFees(
        uint256 feeGrowthGlobalX128,
        uint256 feeGrowthOutsideLowerX128,
        uint256 feeGrowthOutsideUpperX128,
        uint256 feeGrowthInsideLastX128,
        int24 tick,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) private view returns (uint256 fee) {
        
        uint256 feeGrowthBelowX128 = (tick >= tickLower) ? feeGrowthOutsideLowerX128 : (feeGrowthGlobalX128 - feeGrowthOutsideLowerX128);
        uint256 feeGrowthAboveX128 = (tick < tickUpper) ? feeGrowthOutsideUpperX128 : (feeGrowthGlobalX128 - feeGrowthOutsideUpperX128);

        uint256 feeGrowthInsideX128 = feeGrowthGlobalX128 - feeGrowthBelowX128 - feeGrowthAboveX128;
        fee = FullMath.mulDiv(liquidity, feeGrowthInsideX128 - feeGrowthInsideLastX128, FixedPoint128_Q128);
    }

    function returnFund(
        address _account, 
        uint256 _amount0,
        uint256 _amount1
        ) 
        internal 
    {
        token0.safeTransfer(_account, _amount0);
        token1.safeTransfer(_account, _amount1);
    }
}