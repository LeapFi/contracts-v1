// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "../interface/gmx/IGmxPositionRouter.sol";
import "../interface/gmx/IGmxRouter.sol";
import "../interface/gmx/IGmxVault.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { FullMath, LiquidityAmounts } from "@arrakisfi/v3-lib-0.8/contracts/LiquidityAmounts.sol";
import { TickMath } from "@arrakisfi/v3-lib-0.8/contracts/TickMath.sol";
import "./MimGmxVault.sol";
import "../peripherals/UniHelper.sol";
import "hardhat/console.sol";

contract DerivioA is ReentrancyGuard {

    using SafeERC20 for IERC20;
    IERC20 immutable token0;
    IERC20 immutable token1;
    IERC20 immutable collateralToken;
    IERC20 immutable indexToken;
    bool immutable isZeroCollateral;
    uint128 private constant precision = 1e10;
    uint256 private constant gmxDecimals = 30;
    uint256 private constant FixedPoint128_Q128 = 0x100000000000000000000000000000000;

    UniHelper private immutable uniHelper;
    IUniswapV3Factory private immutable uniFactory;
    ISwapRouter private immutable swapRouter;
    INonfungiblePositionManager private immutable positionManager;

    IGmxPositionRouter private immutable gmxPositionRouter;
    IGmxRouter private immutable gmxRouter;
    IGmxVault private immutable gmxVault;
    address minAddr;

    // user address => positionIds
    mapping(address => bytes32[]) public positionIds;

    // positionId => ComposedLiquidity
    mapping(bytes32 => ComposedLiquidity) composedLiquidities;

    // user address => nextId
    mapping(address => uint256) public nextId;

    struct ComposedLiquidity {
        bytes32 positionKey;
        uint256 openTime;
        UniV3Position uniV3Position;
        GmxPosition gmxPosition;
    }

    struct UniV3Position {
        int24 tickLower;
        int24 tickUpper;
        uint24 feeTier;
        uint256 tokenId;
        uint128 liquidity;
        FeeGrowthData feeGrowthData;
    }

    struct FeeGrowthData {
        uint256 feeGrowthInside0X128;
        uint256 feeGrowthInside1X128;
        uint256 feeGrowthLast0X128;
        uint256 feeGrowthLast1X128;
    }

    struct GmxPosition {
        address minVault;
        uint256 collateralAmount;
        uint256 shortDelta;
    }

    struct PositionArgs {
        address recipient;
        int24 tickLower;
        int24 tickUpper;
        uint24 feeTier;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint24 shortLeverage;
        uint256 swapMaxSlippage;
        uint256 shortMaxSlippage;
    }

    modifier verifyPositionExists(address _account, bytes32 _positionKey) {

        bytes32[] memory userPositionIds = positionIds[_account];
        bool positionExists = false;
        for (uint i = 0; i < userPositionIds.length; i++) {
            if (userPositionIds[i] == _positionKey) {
                positionExists = true;
                break;
            }
        }
        require(positionExists, "Position does not exist for the given account");
        _;
    }

    constructor (
        UniHelper _uniHelper, 
        IUniswapV3Factory _uniFactory, 
        ISwapRouter _swapRouter,
        INonfungiblePositionManager _positionManager,
        IGmxPositionRouter _gmxPositionRouter,
        IGmxRouter _gmxRouter,
        IGmxVault _gmxVault,
        address _token0,
        address _token1,
        bool _isZeroCollateral
        ) 
    {
        uniHelper = _uniHelper;
        uniFactory = _uniFactory;
        swapRouter = _swapRouter;
        positionManager = _positionManager;
        gmxPositionRouter = _gmxPositionRouter;
        gmxRouter = _gmxRouter;
        gmxVault = _gmxVault;

        token0 = IERC20(_token0);
        token1 = IERC20(_token1);

        isZeroCollateral = _isZeroCollateral;
        collateralToken = _isZeroCollateral ? token0 : token1;
        indexToken = _isZeroCollateral ? token1 : token0;

        _gmxRouter.approvePlugin(address(_gmxPositionRouter));
    }

    function openAS(PositionArgs memory _args, address _account) external nonReentrant {

        _args.amount0Desired = 0;
        IUniswapV3Pool pool = IUniswapV3Pool(uniFactory.getPool(address(token0), address(token1), _args.feeTier));
        uniHelper.validateTickSpacing(pool, _args.tickLower, _args.tickUpper);
        (uint160 sqrtPriceX96, int24 tickCurrent, , , , , ) = pool.slot0();

        token0.safeTransferFrom(msg.sender, address(this), _args.amount0Desired);
        token1.safeTransferFrom(msg.sender, address(this), _args.amount1Desired);
        
        (uint256 amount0Uni, uint256 amount1Uni, ) = calcOptimalAmount(_args, sqrtPriceX96, tickCurrent, false);
        (_args.amount0Desired, _args.amount1Desired) = swapToOptimalAmount(_args.amount0Desired, _args.amount1Desired, amount0Uni, amount1Uni, 0, _args.feeTier);

        uint256 tokenId; uint128 liquidity;
        (
            tokenId,
            liquidity,
            _args.amount0Desired,
            _args.amount1Desired 
        ) = mintLiquidity(_args.tickLower, _args.tickUpper, _args.feeTier, _args.amount0Desired, _args.amount1Desired);

        addPositionInfo(
            _args.recipient,
            _args.tickLower, 
            _args.tickUpper,
            _args.feeTier,
            tokenId,
            liquidity,
            address(0),
            0,
            0
        );

        returnFund(_account, _args.amount0Desired, _args.amount1Desired);
    }

    function openAL(PositionArgs memory _args, address _account) external payable nonReentrant {

        _args.amount0Desired = 0;
        IUniswapV3Pool pool = IUniswapV3Pool(uniFactory.getPool(address(token0), address(token1), _args.feeTier));
        uniHelper.validateTickSpacing(pool, _args.tickLower, _args.tickUpper);
        (uint160 sqrtPriceX96, int24 tickCurrent, , , , , ) = pool.slot0();

        token0.safeTransferFrom(msg.sender, address(this), _args.amount0Desired);
        token1.safeTransferFrom(msg.sender, address(this), _args.amount1Desired);
        
        (uint256 amount0Uni, uint256 amount1Uni, uint256 collateralAmount) = calcOptimalAmount(_args, sqrtPriceX96, tickCurrent, true);
        (_args.amount0Desired, _args.amount1Desired) = swapToOptimalAmount(_args.amount0Desired, _args.amount1Desired, amount0Uni, amount1Uni, collateralAmount, _args.feeTier);

        uint256 tokenId; uint128 liquidity;
        (
            tokenId,
            liquidity,
            _args.amount0Desired,
            _args.amount1Desired 
        ) = 
            mintLiquidity(_args.tickLower, _args.tickUpper, _args.feeTier, _args.amount0Desired, _args.amount1Desired);

        uint256 shortDelta = collateralAmount * 1;
        address minVault = openGmxShort(_args.recipient, collateralAmount, shortDelta, 0);

        addPositionInfo(
            _args.recipient,
            _args.tickLower, 
            _args.tickUpper,
            _args.feeTier,
            tokenId,
            liquidity,
            minVault,
            collateralAmount,
            shortDelta
        );

        returnFund(_account, _args.amount0Desired, _args.amount1Desired);
    }

    function closeAS(address _account, bytes32 _positionKey) 
        external nonReentrant 
        verifyPositionExists(_account, _positionKey)
    {
        ComposedLiquidity memory composedLiquidity = composedLiquidities[_positionKey];

        (uint256 collect0, uint256 collect1)  = withdrawLiquidity(_account, _positionKey);
        (collect0, collect1)  = swapToCollateral(collect0, collect1, composedLiquidity.uniV3Position.feeTier);

        returnFund(_account, collect0, collect1);
    }

    function closeAL(address _account, bytes32 _positionKey) 
        external payable nonReentrant 
        verifyPositionExists(_account, _positionKey)
    {
        closeGmxShort(_account, _positionKey, 0, type(uint256).max);
        ComposedLiquidity memory composedLiquidity = composedLiquidities[_positionKey];
        
        (uint256 collect0, uint256 collect1)  = withdrawLiquidity(_account, _positionKey);
        (collect0, collect1)  = swapToCollateral(collect0, collect1, composedLiquidity.uniV3Position.feeTier);

        returnFund(_account, collect0, collect1);
    }

    function swapToOptimalAmount(
        uint256 _amount0Desired,
        uint256 _amount1Desired,
        uint256 _amount0Uni,
        uint256 _amount1Uni,
        uint256 _collateralAmount,
        uint24 _feeTier
    )
        private
        returns (uint256 _amount0Out, uint256 _amount1Out)
    {
        if (isZeroCollateral) {
            _amount0Uni += _collateralAmount;
        }
        else {
            _amount1Uni += _collateralAmount;
        }

        uint256 amount0Swap; uint256 amount1Swap;
        if (_amount0Desired > _amount0Uni) {
            amount0Swap = _amount0Desired - _amount0Uni;
        }
        else if (_amount1Desired > _amount1Uni) {
            amount1Swap = _amount1Desired - _amount1Uni;
        }

        if (amount1Swap > 0) {
            _amount1Desired -= amount1Swap;
            _amount0Desired += swapExactInputSingle(token1, token0, amount1Swap, _feeTier);
        }
        else if (amount0Swap > 0) {
            _amount0Desired -= amount0Swap;
            _amount1Desired += swapExactInputSingle(token0, token1, amount0Swap, _feeTier);
        }

        if (isZeroCollateral) {
            _amount0Desired -= _collateralAmount;
        }
        else {
            _amount1Desired -= _collateralAmount;
        }

        _amount0Out = _amount0Desired;
        _amount1Out = _amount1Desired;
    }

    function swapToCollateral(uint256 _collect0, uint256 _collect1, uint24 _feeTier) internal returns (uint256 amount0, uint256 amount1) {

        amount0 = _collect0;
        amount1 = _collect1;

        // Swap the non-collateral token to the collateral token
        if (isZeroCollateral) {
            // Swap token1 to token0 (collateral)
            amount0 += swapExactInputSingle(token1, token0, _collect1, _feeTier);
            amount1 = 0;
        } else {
            // Swap token0 to token1 (collateral)
            amount0 = 0;
            amount1 += swapExactInputSingle(token0, token1, _collect0, _feeTier);
        }
    }

    function calcOptimalAmount(
        PositionArgs memory _args,
        uint160 _sqrtPriceX96, 
        int24 _tickCurrent,
        bool _isShort
    )
        public
        returns (uint256 amount0Uni, uint256 amount1Uni, uint256 amountCollateral)
    {
        uint256 amount0Total = _args.amount0Desired + uniHelper.amount1ToAmount0(_args.amount1Desired, _sqrtPriceX96);

        if (_isShort) {
            (uint256 amount0TotalSim, , , , uint256 amountLowerSim, ) = uniHelper.ratioAtTick(_tickCurrent, _args.tickLower, _args.tickUpper, false);
            amountCollateral = amount0Total * amountLowerSim / amount0TotalSim;
            amount0Total -= amountCollateral;

            if (!isZeroCollateral) {
                amountCollateral = uniHelper.amount0ToAmount1(amountCollateral, _sqrtPriceX96);
            }
        }

        if (_tickCurrent > _args.tickUpper) {
            _tickCurrent = _args.tickUpper;
        }
        else if (_tickCurrent < _args.tickLower) {
            _tickCurrent = _args.tickLower;
        }

        amount0Uni = amount0Total * uint256(int256(_args.tickUpper - _tickCurrent)) / uint256(int256(_args.tickUpper - _args.tickLower));
        amount1Uni = uniHelper.amount0ToAmount1(amount0Total - amount0Uni, _sqrtPriceX96);
    }

    function openGmxShort(
        address _recipient,
        uint256 _collateralAmount,
        uint256 _shortDelta,
        uint256 _acceptPrice
    ) 
        private
        returns (address)
    {
        console.log("openGmxShort.....");
        require(_shortDelta >= _collateralAmount, "delta size too samll");
        
        MimGmxVault mimGmxVault = new MimGmxVault(
            _recipient,
            gmxPositionRouter,
            gmxRouter,
            gmxVault,
            address(collateralToken),
            address(indexToken)
            );
        
        _shortDelta *= 10 ** (gmxDecimals - uint256(IERC20Metadata(address(collateralToken)).decimals())); 

        console.log("_shortDelta: %s", _shortDelta);
        console.log("_collateralAmount: %s", _collateralAmount);

        collateralToken.safeTransfer(address(mimGmxVault), _collateralAmount);
        mimGmxVault.openGmxShort{ value: msg.value }(
            _collateralAmount, 
            _shortDelta, 
            _acceptPrice
            );
        mimGmxVault.getGmxPosition();
        minAddr = address(mimGmxVault);

        return address(mimGmxVault);
    }

    function closeGmxShort(address _recipient, bytes32 _positionKey, uint256 _minOut, uint256 _acceptablePrice) 
        internal 
    {
        ComposedLiquidity memory composedLiquidity = composedLiquidities[_positionKey];
        address mimGmxVaultAddress = composedLiquidity.gmxPosition.minVault;

        // Ensure that the position actually exists
        require(mimGmxVaultAddress != address(0), "Position not found");

        // Call closeGmxShort on the MimGmxVault contract
        MimGmxVault(mimGmxVaultAddress).closeGmxShort{ value: msg.value }(_recipient, _minOut, _acceptablePrice);
    }

    function addPositionInfo(
        address _recipient,
        int24 _tickLower, 
        int24 _tickUpper,
        uint24 _feeTier,
        uint256 _tokenId,
        uint128 _liquidity,
        address _minVault,
        uint256 _collateralAmount,
        uint256 _shortDelta
    )
        private
    {

        UniV3Position memory uniV3Position;
        uniV3Position.tickLower = _tickLower;
        uniV3Position.tickUpper = _tickUpper;
        uniV3Position.feeTier = _feeTier;
        uniV3Position.tokenId = _tokenId;
        uniV3Position.liquidity = _liquidity;

        GmxPosition memory gmxPosition;
        gmxPosition.minVault = _minVault;
        gmxPosition.collateralAmount = _collateralAmount;
        gmxPosition.shortDelta = _shortDelta;

        ComposedLiquidity memory position;
        position.positionKey = getNextPositionKey(_recipient, _tokenId, _minVault);
        position.openTime = block.timestamp;
        position.uniV3Position = uniV3Position;
        position.gmxPosition = gmxPosition;

        positionIds[_recipient].push(position.positionKey);
        composedLiquidities[position.positionKey] = position;

        updateUniPosition(position.positionKey);
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
                delete composedLiquidities[_positionKey];

                // The element has been removed, no need to continue the loop
                return;
            }
        }
    }

    function updateUniPosition(bytes32 _positionKey) private {

        ComposedLiquidity storage composedLiquidity = composedLiquidities[_positionKey];
        bytes32 uniKey = keccak256(abi.encodePacked(address(this), composedLiquidity.uniV3Position.tickLower, composedLiquidity.uniV3Position.tickUpper));
        (
            ,
            ,
            ,
            composedLiquidity.uniV3Position.feeGrowthData.feeGrowthInside0X128,
            composedLiquidity.uniV3Position.feeGrowthData.feeGrowthInside1X128
        ) =
            IUniswapV3Pool(uniFactory.getPool(address(token0), address(token1), composedLiquidity.uniV3Position.feeTier)).positions(uniKey);

        (
            composedLiquidity.uniV3Position.feeGrowthData.feeGrowthLast0X128, 
            composedLiquidity.uniV3Position.feeGrowthData.feeGrowthLast1X128
        ) = 
            computeFeeGrowth(_positionKey);

    }

    function getGmxPosition() 
        public
    {
        console.log("getGmxPosition.....");
        MimGmxVault(minAddr).getGmxPosition();
    }

    function positionsOf(
        bytes32 _positionId
    )
        public
        view
        returns (ComposedLiquidity memory)
    {
        return composedLiquidities[_positionId];
    }

    function getAllPositionIds(
        address _account
    )
        public
        view
        returns (bytes32[] memory)
    {
        return positionIds[_account];
    }

    function getNextPositionKey( 
        address _recipient,
        uint256 _tokenId,
        address _minVault
    )
        private
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(
            nextId[_recipient]++,
            _tokenId,
            _minVault
        ));
    }

    function getNextKey( 
        address _recipient
    )
        public
        returns (uint256)
    {
        return nextId[_recipient];
    }

    function mintLiquidity(
        int24 _tickLower, 
        int24 _tickUpper, 
        uint24 _feeTier,
        uint256 _amount0, 
        uint256 _amount1
        ) 
        private 
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1)
    {
        // Approve the Uniswap V3 contract to spend the tokens on behalf of this contract
        token0.approve(address(positionManager), _amount0);
        token1.approve(address(positionManager), _amount1);

        console.log("desired..");
        console.log("_amount0: %s", _amount0);
        console.log("_amount1: %s", _amount1);

        // Mint the position
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: _feeTier,
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            amount0Desired: _amount0,
            amount1Desired: _amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        uint256 amount0Minted; uint256 amount1Minted;
        (
            tokenId,
            liquidity,
            amount0Minted,
            amount1Minted
        ) = positionManager.mint(params);

        amount0 = _amount0 - amount0Minted;
        amount1 = _amount1 - amount1Minted;

        console.log("minting..");
        console.log("amount0Minted: %s", amount0Minted);
        console.log("amount1Minted: %s", amount1Minted);
    }

    function swapExactInputSingle(
        IERC20 _tokenIn,
        IERC20 _tokenOut,
        uint256 _amountIn,
        uint24 _feeTier
    ) 
        internal 
        returns (uint256 amountOut)
    {
        // Approve the router to spend token.
        _tokenIn.approve(address(swapRouter), _amountIn);

        // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
        // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(_tokenIn),
                tokenOut: address(_tokenOut),
                fee: _feeTier,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);
    }
    
    function withdrawLiquidity(
        address _recipient,
        bytes32 _positionKey) 
        public 
        returns (uint256 collect0, uint256 collect1) 
    {
        ComposedLiquidity memory composedLiquidity = positionsOf(_positionKey);

        // Decrease liquidity to zero
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: composedLiquidity.uniV3Position.tokenId,
            liquidity: composedLiquidity.uniV3Position.liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });
        (uint256 burn0, uint256 burn1) = positionManager.decreaseLiquidity(decreaseLiquidityParams);

        // Remove liquidity and collect fees
        (uint256 fee0, uint256 fee1) = unCollectedFee(_positionKey);
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: composedLiquidity.uniV3Position.tokenId,
            recipient: address(this),
            amount0Max: uint128(burn0 + fee0),
            amount1Max: uint128(burn1 + fee1)
        });
        (collect0, collect1) = positionManager.collect(collectParams);

        updateUniPosition(_positionKey);
        removePositionKey(_recipient, _positionKey);

        console.log("withdraw..");
        console.log("burn0: ", burn0);
        console.log("burn1: ", burn1);
        console.log("fee0: ", fee0);
        console.log("fee1: ", fee1);
        console.log("collect0: ", collect0);
        console.log("collect1: ", collect1);
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

        ComposedLiquidity memory composedLiquidity = positionsOf(_positionKey);

        fee0 = feeGrowth0 - composedLiquidity.uniV3Position.feeGrowthData.feeGrowthLast0X128;
        fee1 = feeGrowth1 - composedLiquidity.uniV3Position.feeGrowthData.feeGrowthLast1X128;

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

        ComposedLiquidity memory composedLiquidity = positionsOf(_positionKey);

        fee0 = computeUncollectedFees(
            pool.feeGrowthGlobal0X128(),
            feeGrowthOutside0Lower,
            feeGrowthOutside0Upper,
            composedLiquidity.uniV3Position.feeGrowthData.feeGrowthInside0X128,
            tickCurrent,
            tickLower,
            tickUpper,
            composedLiquidity.uniV3Position.liquidity
        );

        fee1 = computeUncollectedFees(
            pool.feeGrowthGlobal1X128(),
            feeGrowthOutside1Lower,
            feeGrowthOutside1Upper,
            composedLiquidity.uniV3Position.feeGrowthData.feeGrowthInside1X128,
            tickCurrent,
            tickLower,
            tickUpper,
            composedLiquidity.uniV3Position.liquidity
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
        ComposedLiquidity memory composedLiquidity = positionsOf(_positionKey);
        
        tickLower = composedLiquidity.uniV3Position.tickLower;
        tickUpper = composedLiquidity.uniV3Position.tickUpper;
        liquidity = composedLiquidity.uniV3Position.liquidity;

        // Calculate uncollected fees
        pool = IUniswapV3Pool(uniFactory.getPool(address(token0), address(token1), composedLiquidity.uniV3Position.feeTier));

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