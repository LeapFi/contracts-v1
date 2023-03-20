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
        ) = mintLiquidity(_args.tickLower, _args.tickUpper, _args.feeTier, _args.amount0Desired, _args.amount1Desired);

        uint256 shortDelta = collateralAmount * 1;
        address minVault = openGmxShort(collateralAmount, shortDelta, 0);

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

        // Calculate which amount should be swap to optimal ratio
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
        mimGmxVault.openGmxShort{value: msg.value}(
            _collateralAmount, 
            _shortDelta, 
            _acceptPrice
            );
        mimGmxVault.getGmxPosition();
        minAddr = address(mimGmxVault);

        return address(mimGmxVault);
    }

    function openGmxShort2(
        uint256 _collateralAmount,
        uint256 _sizeDelta,
        uint256 _acceptPrice
    ) 
        payable
        external
    { 
        token1.safeTransferFrom(msg.sender, address(this), _collateralAmount);
        IERC20(collateralToken).approve(address(gmxRouter), _collateralAmount);

        address[] memory path = new address[](1);
        path[0] = address(token1);
        bool isLong = false;
        bytes32 referralCode = 0;

        console.log("path[0]: %s", path[0]);
        console.log("indexToken %s", address(indexToken));
        console.log("_collateralAmount %s", _collateralAmount);
        console.log("_sizeDelta %s", _sizeDelta);
        console.log("isLong %s", isLong);

        gmxPositionRouter.createIncreasePosition{value: msg.value}(
            path, 
            address(indexToken), 
            _collateralAmount,
            0,
            _sizeDelta, 
            isLong, 
            _acceptPrice, 
            2e16,
            referralCode,
            address(0)
        );

        getGmxPosition2();
    }

    function getGmxPosition2() 
        public
    {
        (uint256 sizeDelta, uint256 collateral, , , , , , ) = gmxVault.getPosition(address(this), address(collateralToken), address(indexToken), false);
        console.log("sizeDelta: %s", sizeDelta);
        console.log("collateral: %s", collateral);
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
    
    /// @notice Collects the fees associated with provided liquidity
    /// @dev The contract must hold the erc721 token before it can collect fees
    /// @param _tokenId The id of the erc721 token
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collectAllFees(
        address _account, 
        address _recipient, 
        bytes32 _positionId, 
        uint256 _tokenId
        ) 
        external 
        returns (uint256 amount0, uint256 amount1) 
    {
        // Get position details
        ( , , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , ,) = positionManager.positions(_tokenId);
        ComposedLiquidity memory composedLiquidity = positionsOf(_positionId);

        // Calculate uncollected fees
        IUniswapV3Pool pool = IUniswapV3Pool(uniFactory.getPool(address(token0), address(token1), composedLiquidity.uniV3Position.feeTier));
        (, , , uint256 fees0, uint256 fees1) = pool.positions(keccak256(abi.encodePacked(address(this), tickLower, tickUpper)));

        // Calculate uncollected fees per account
        uint128 fee0 = uint128(fees0) * composedLiquidity.uniV3Position.liquidity / liquidity;
        uint128 fee1 = uint128(fees1) * composedLiquidity.uniV3Position.liquidity / liquidity;

        // set amount0Max and amount1Max to uint256.max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        INonfungiblePositionManager.CollectParams memory params =
            INonfungiblePositionManager.CollectParams({
                tokenId: _tokenId,
                recipient: address(this),
                amount0Max: fee0,
                amount1Max: fee1
            });

        (amount0, amount1) = positionManager.collect(params);

        returnFund(_recipient, amount0, amount1);
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