// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { FullMath, LiquidityAmounts } from "@arrakisfi/v3-lib-0.8/contracts/LiquidityAmounts.sol";
import { TickMath } from "@arrakisfi/v3-lib-0.8/contracts/TickMath.sol";
import "./OrderManager.sol";
import "../protocols-manager/GmxManager.sol";
import "../protocols-manager/UniV3Manager.sol";
import "./interface/IDerivioPositionManager.sol";
import "../peripherals/UniHelper.sol";
import "hardhat/console.sol";

contract DerivioA is ReentrancyGuard {

    address public admin;
    mapping (address => bool) public isLiquidator;

    using SafeERC20 for IERC20;
    IERC20 public token0;
    IERC20 public token1;
    IERC20 public collateralToken;
    IERC20 public indexToken;
    bool public isZeroCollateral;

    IDerivioPositionManager private immutable derivioPositionManager;
    OrderManager private immutable orderManager;
    UniV3Manager private immutable uniV3Manager;
    GmxManager private immutable gmxManager;

    UniHelper private immutable uniHelper;
    IUniswapV3Factory private immutable uniFactory;
    ISwapRouter private immutable swapRouter;

    uint256 private constant leverageDenominator = 1e6;

    struct OpenArgs {
        address recipient;
        int24 tickLower;
        int24 tickUpper;
        uint24 feeTier;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint24 shortLeverage;
        uint160 swapSqrtPriceLimitX96;
        uint256 shortPriceLimit;
    }
    
    struct CloaseArgs {
        bytes32 positionKey;
        bool swapToCollateral;
    }

    event SetLiquidator(address account, bool isActive);

    modifier onlyAdmin() {
        require(msg.sender == admin, "DerivioA: forbidden");
        _;
    }

    modifier onlyLiquidator() {
        require(isLiquidator[msg.sender], "DerivioA: forbidden");
        _;
    }

    constructor (
        address _admin,
        UniHelper _uniHelper, 
        IUniswapV3Factory _uniFactory, 
        ISwapRouter _swapRouter,
        IDerivioPositionManager _derivioPositionManager,
        OrderManager _orderManager,
        UniV3Manager _uniV3Manager,
        GmxManager _gmxManager,
        address _token0,
        address _token1,
        bool _isZeroCollateral
        ) 
    {
        admin = _admin;
        
        uniHelper = _uniHelper;
        uniFactory = _uniFactory;
        swapRouter = _swapRouter;

        derivioPositionManager = _derivioPositionManager;
        orderManager = _orderManager;
        uniV3Manager = _uniV3Manager;
        gmxManager = _gmxManager;
        
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);

        isZeroCollateral = _isZeroCollateral;
        collateralToken = _isZeroCollateral ? token0 : token1;
        indexToken = _isZeroCollateral ? token1 : token0;
    }

    function setLiquidator(address _account, bool _isActive) public onlyAdmin {
        isLiquidator[_account] = _isActive;
        emit SetLiquidator(_account, _isActive);
    }

    function openAS(OpenArgs memory _args) 
        external nonReentrant 
        returns (IDerivioPositionManager.OpenInfo memory)
    {
        console.log('_args.swapSqrtPriceLimitX96:', _args.swapSqrtPriceLimitX96);
        console.log('recover:', uniHelper.sqrtPriceX96ToPrice(uint160(_args.swapSqrtPriceLimitX96)));
        
        IUniswapV3Pool pool = IUniswapV3Pool(uniFactory.getPool(address(token0), address(token1), _args.feeTier));
        uniHelper.validateTickSpacing(pool, _args.tickLower, _args.tickUpper);
        (uint160 sqrtPriceX96, int24 tickCurrent, , , , , ) = pool.slot0();

        token0.safeTransferFrom(msg.sender, address(this), _args.amount0Desired);
        token1.safeTransferFrom(msg.sender, address(this), _args.amount1Desired);
        
        (uint256 amount0Uni, uint256 amount1Uni, , ) = calcOptimalAmount(_args, sqrtPriceX96, tickCurrent);
        (_args.amount0Desired, _args.amount1Desired) = swapToOptimalAmount(_args.amount0Desired, _args.amount1Desired, amount0Uni, amount1Uni, 0, _args.feeTier, _args.swapSqrtPriceLimitX96); 
        
        // Update current price
        (sqrtPriceX96, tickCurrent, , , , , ) = pool.slot0();

        // Prepare protocol open arguments
        IDerivioPositionManager.OpenArg[] memory openArgs = new IDerivioPositionManager.OpenArg[](1);
        openArgs[0] = createUniV3OpenArg(_args, sqrtPriceX96);

        token0.approve(address(uniV3Manager), _args.amount0Desired);
        token1.approve(address(uniV3Manager), _args.amount1Desired);

        // Open position in the protocol
        return derivioPositionManager.openProtocolsPosition(_args.recipient, openArgs, 0);
    }

    function openAL(OpenArgs memory _args) 
        external payable nonReentrant 
        returns (IDerivioPositionManager.OpenInfo memory)
    {
        IUniswapV3Pool pool = IUniswapV3Pool(uniFactory.getPool(address(token0), address(token1), _args.feeTier));
        uniHelper.validateTickSpacing(pool, _args.tickLower, _args.tickUpper);
        (uint160 sqrtPriceX96, int24 tickCurrent, , , , , ) = pool.slot0();

        token0.safeTransferFrom(msg.sender, address(this), _args.amount0Desired);
        token1.safeTransferFrom(msg.sender, address(this), _args.amount1Desired);
        
        (uint256 amount0Uni, uint256 amount1Uni, uint256 collateralAmount, uint256 shortDelta) = calcOptimalAmount(_args, sqrtPriceX96, tickCurrent);
        (_args.amount0Desired, _args.amount1Desired) = swapToOptimalAmount(_args.amount0Desired, _args.amount1Desired, amount0Uni, amount1Uni, collateralAmount, _args.feeTier, _args.swapSqrtPriceLimitX96);

        // Update current price
        (sqrtPriceX96, , , , , , ) = pool.slot0();
        
        // Prepare protocol open arguments
        IDerivioPositionManager.OpenArg[] memory openArgs = new IDerivioPositionManager.OpenArg[](2);
        openArgs[0] = createUniV3OpenArg(_args, sqrtPriceX96);
        openArgs[1] = createGmxOpenArg(collateralAmount, shortDelta, _args.shortPriceLimit);

        token0.approve(address(uniV3Manager), _args.amount0Desired);
        token1.approve(address(uniV3Manager), _args.amount1Desired);
        collateralToken.approve(address(gmxManager), collateralAmount);

        // Open positions
        return derivioPositionManager.openProtocolsPosition{ value: gmxManager.minExecutionFee() }(_args.recipient, openArgs, orderManager.keeperFeeOf(0));
    }

    function createUniV3OpenArg(OpenArgs memory _args, uint160 _sqrtPriceX96Current) 
        internal view 
        returns (IDerivioPositionManager.OpenArg memory uniV3Arg) 
    {
        uint160 sqrtPriceX96Lower = TickMath.getSqrtRatioAtTick(_args.tickLower);
        uint160 sqrtPriceX96Upper = TickMath.getSqrtRatioAtTick(_args.tickUpper);
        uint128 liquidityDesired = 
            LiquidityAmounts.getLiquidityForAmounts(_sqrtPriceX96Current, sqrtPriceX96Lower, sqrtPriceX96Upper, _args.amount0Desired, _args.amount1Desired);
        
        uniV3Arg = IDerivioPositionManager.OpenArg({
            manager: uniV3Manager,
            value: 0,
            funds: new IProtocolPositionManager.Fund[](2),
            inputs: abi.encode(
                _args.tickLower,
                _args.tickUpper,
                _args.feeTier,
                _args.amount0Desired,
                _args.amount1Desired,
                liquidityDesired
            )
        });

        uniV3Arg.funds[0].token = address(token0);
        uniV3Arg.funds[1].token = address(token1);

        uniV3Arg.funds[0].amount = _args.amount0Desired;
        uniV3Arg.funds[1].amount = _args.amount1Desired;

        return uniV3Arg;
    }

    function createGmxOpenArg(uint256 _collateralAmount, uint256 _shortDelta, uint256 _shortPriceLimit) 
        internal view 
        returns (IDerivioPositionManager.OpenArg memory gmxArg) 
    {
        gmxArg = IDerivioPositionManager.OpenArg({
            manager: gmxManager,
            value: gmxManager.minExecutionFee(),
            funds: new IProtocolPositionManager.Fund[](1),
            inputs: abi.encode(
                address(collateralToken),
                address(indexToken),
                false, // short
                _collateralAmount,
                _shortDelta,
                _shortPriceLimit
            )
        });

        gmxArg.funds[0].token = address(collateralToken);
        gmxArg.funds[0].amount = _collateralAmount;
    }

    function closePosition(address _account, CloaseArgs memory _args)
        public payable nonReentrant 
        returns (IDerivioPositionManager.CloseResult[] memory closedPositions_)
    {
        IDerivioPositionManager.OpenInfo memory position = derivioPositionManager.positionOf(_args.positionKey);
        IDerivioPositionManager.CloseArg[] memory protocolCloseArgs = new IDerivioPositionManager.CloseArg[](position.openResults.length);
        uint256 sumValue = 0;

        for (uint i = 0; i < position.openResults.length; i++) {
            if (position.openResults[i].manager == uniV3Manager) {
                protocolCloseArgs[i] = IDerivioPositionManager.CloseArg({
                    manager: uniV3Manager,
                    inputs: abi.encode(position.openResults[i].key),
                    value: 0
                });
            } else if (position.openResults[i].manager == gmxManager) {

                uint256 executionFee = gmxManager.minExecutionFee();

                protocolCloseArgs[i] = IDerivioPositionManager.CloseArg({
                    manager: gmxManager,
                    inputs: abi.encode(position.openResults[i].key, uint256(0), type(uint256).max),
                    value: executionFee
                });

                sumValue += executionFee;
            }
        }

        // Call closeProtocolsPosition
        closedPositions_ = derivioPositionManager.closeProtocolsPosition{ value: sumValue }(_account, _args.positionKey, protocolCloseArgs);

        for (uint i = 0; i < closedPositions_.length; i++) {
            if (closedPositions_[i].manager == uniV3Manager) {
                
                uint256 collect0 = closedPositions_[i].funds[0].amount;
                uint256 collect1 = closedPositions_[i].funds[1].amount;

                if (_args.swapToCollateral) {
                    uint24 feeTier = 500;
                    (collect0, collect1) = swapToCollateral(collect0, collect1, feeTier, 0);
                }
                
                // Return the funds to the account
                returnFund(_account, collect0, collect1);

            } else if (closedPositions_[i].manager == gmxManager) {
                // Handle GMX closed position if needed
            }
        }
    }

    function liquidatePosition(address payable _account, CloaseArgs memory _args) 
        external payable onlyLiquidator 
        returns (IDerivioPositionManager.CloseResult[] memory closedPositions_)
    {
        require(derivioPositionManager.validatedIsLiquidated(_args.positionKey), "no protocol position is liquidated");

        orderManager.transferOutETH(derivioPositionManager.keeperFee(_args.positionKey), payable(msg.sender));

        return closePosition(_account, _args);
    }
 
    function swapToOptimalAmount(
        uint256 _amount0Desired,
        uint256 _amount1Desired,
        uint256 _amount0Uni,
        uint256 _amount1Uni,
        uint256 _collateralAmount,
        uint24 _feeTier,
        uint160 _sqrtPriceLimitX96
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
            _amount0Desired += swapExactInputSingle(token1, token0, amount1Swap, _feeTier, _sqrtPriceLimitX96);
        }
        else if (amount0Swap > 0) {
            _amount0Desired -= amount0Swap;
            _amount1Desired += swapExactInputSingle(token0, token1, amount0Swap, _feeTier, _sqrtPriceLimitX96);
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

    function swapToCollateral(uint256 _collect0, uint256 _collect1, uint24 _feeTier, uint160 _sqrtPriceLimitX96) internal returns (uint256 amount0, uint256 amount1) {

        amount0 = _collect0;
        amount1 = _collect1;

        // Swap the non-collateral token to the collateral token
        if (isZeroCollateral) {
            // Swap token1 to token0 (collateral)
            amount0 += swapExactInputSingle(token1, token0, _collect1, _feeTier, _sqrtPriceLimitX96);
            amount1 = 0;
        } else {
            // Swap token0 to token1 (collateral)
            amount0 = 0;
            amount1 += swapExactInputSingle(token0, token1, _collect0, _feeTier, _sqrtPriceLimitX96);
        }
    }

    function calcOptimalAmount(
        OpenArgs memory _args,
        uint160 _sqrtPriceX96, 
        int24 _tickCurrent
    )
        public
        returns (uint256 amount0Uni, uint256 amount1Uni, uint256 amountCollateral, uint256 shortDelta)
    {
        uint256 amount0Total = _args.amount0Desired + uniHelper.amount1ToAmount0(_args.amount1Desired, _sqrtPriceX96);

        if (_args.shortLeverage != 0) {
            require(_args.shortLeverage >= leverageDenominator, "shortLeverage too small");

            (uint256 amount0TotalSim, , , , uint256 amount0LowerSim, ) = uniHelper.ratioAtTick(_tickCurrent, _args.tickLower, _args.tickUpper, false);
            amountCollateral = amount0Total * amount0LowerSim / amount0TotalSim;

            // apply leverage
            shortDelta = amountCollateral;
            amountCollateral = amountCollateral * leverageDenominator / _args.shortLeverage;

            amount0Total -= amountCollateral;

            if (!isZeroCollateral) {
                amountCollateral = uniHelper.amount0ToAmount1(amountCollateral, _sqrtPriceX96);
                shortDelta = uniHelper.amount0ToAmount1(shortDelta, _sqrtPriceX96);
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

    function swapExactInputSingle(
        IERC20 _tokenIn,
        IERC20 _tokenOut,
        uint256 _amountIn,
        uint24 _feeTier,
        uint160 _sqrtPriceLimitX96
    ) 
        internal 
        returns (uint256 amountOut)
    {
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
                sqrtPriceLimitX96: _sqrtPriceLimitX96
            });

        uint256 tokenInBalanceBefore = _tokenIn.balanceOf(address(this));

        _tokenIn.approve(address(swapRouter), _amountIn);
        amountOut = swapRouter.exactInputSingle(params);

        uint256 tokenInBalanceAfter = _tokenIn.balanceOf(address(this));
        require(tokenInBalanceBefore - tokenInBalanceAfter == _amountIn, "Price limit error");
    }

    function returnFund(address _account, uint256 _amount0, uint256 _amount1) 
        internal 
    {
        token0.safeTransfer(_account, _amount0);
        token1.safeTransfer(_account, _amount1);
    }
}