// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { FullMath, LiquidityAmounts } from "@arrakisfi/v3-lib-0.8/contracts/LiquidityAmounts.sol";
import { TickMath } from "@arrakisfi/v3-lib-0.8/contracts/TickMath.sol";
import "../protocols-manager/GmxManager.sol";
import "../protocols-manager/UniV3Manager.sol";
import "./DerivioPositionManager.sol";
import "../peripherals/UniHelper.sol";
import "hardhat/console.sol";

contract DerivioA is ReentrancyGuard {

    using SafeERC20 for IERC20;
    IERC20 public token0;
    IERC20 public token1;
    IERC20 public collateralToken;
    IERC20 public indexToken;
    bool public isZeroCollateral;

    DerivioPositionManager private immutable derivioPositionManager;
    UniV3Manager private immutable uniV3Manager;
    GmxManager private immutable gmxManager;

    UniHelper private immutable uniHelper;
    IUniswapV3Factory private immutable uniFactory;
    ISwapRouter private immutable swapRouter;

    uint256 private constant shortDenominator = 1e6;

    struct PositionArgs {
        address recipient;
        uint256 value;
        int24 tickLower;
        int24 tickUpper;
        uint24 feeTier;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint24 shortLeverage;
        uint256 swapMaxSlippage;
        uint256 shortMaxSlippage;
    }
    
    struct DerivioACloseArgs {
        uint256 value;
        bytes32 positionKey;
        bool swapToCollateral;
    }

    constructor (
        UniHelper _uniHelper, 
        IUniswapV3Factory _uniFactory, 
        ISwapRouter _swapRouter,
        DerivioPositionManager _derivioPositionManager,
        UniV3Manager _uniV3Manager,
        GmxManager _gmxManager,
        address _token0,
        address _token1,
        bool _isZeroCollateral
        ) 
    {
        uniHelper = _uniHelper;
        uniFactory = _uniFactory;
        swapRouter = _swapRouter;

        derivioPositionManager = DerivioPositionManager(_derivioPositionManager);
        uniV3Manager = UniV3Manager(_uniV3Manager);
        gmxManager = GmxManager(_gmxManager);
        
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);

        isZeroCollateral = _isZeroCollateral;
        collateralToken = _isZeroCollateral ? token0 : token1;
        indexToken = _isZeroCollateral ? token1 : token0;
    }

    function openAS(PositionArgs memory _args) 
        external nonReentrant 
        returns (DerivioPositionManager.ProtocolOpenResult[] memory)
    {
        IUniswapV3Pool pool = IUniswapV3Pool(uniFactory.getPool(address(token0), address(token1), _args.feeTier));
        uniHelper.validateTickSpacing(pool, _args.tickLower, _args.tickUpper);
        (uint160 sqrtPriceX96, int24 tickCurrent, , , , , ) = pool.slot0();

        token0.safeTransferFrom(msg.sender, address(this), _args.amount0Desired);
        token1.safeTransferFrom(msg.sender, address(this), _args.amount1Desired);
        
        (uint256 amount0Uni, uint256 amount1Uni, , ) = calcOptimalAmount(_args, sqrtPriceX96, tickCurrent, _args.shortLeverage);
        (_args.amount0Desired, _args.amount1Desired) = swapToOptimalAmount(_args.amount0Desired, _args.amount1Desired, amount0Uni, amount1Uni, 0, _args.feeTier);
               
        // Prepare protocol open arguments
        DerivioPositionManager.ProtocolOpenArg[] memory openArgs = new DerivioPositionManager.ProtocolOpenArg[](1);
        openArgs[0] = createUniV3ProtocolOpenArg(_args, sqrtPriceX96);

        token0.approve(address(uniV3Manager), _args.amount0Desired);
        token1.approve(address(uniV3Manager), _args.amount1Desired);
 
        // Open position in the protocol
        return derivioPositionManager.openProtocolsPosition(_args.recipient, openArgs);
    }

    function openAL(PositionArgs memory _args) 
        external payable nonReentrant 
        returns (DerivioPositionManager.ProtocolOpenResult[] memory)
    {
        IUniswapV3Pool pool = IUniswapV3Pool(uniFactory.getPool(address(token0), address(token1), _args.feeTier));
        uniHelper.validateTickSpacing(pool, _args.tickLower, _args.tickUpper);
        (uint160 sqrtPriceX96, int24 tickCurrent, , , , , ) = pool.slot0();

        token0.safeTransferFrom(msg.sender, address(this), _args.amount0Desired);
        token1.safeTransferFrom(msg.sender, address(this), _args.amount1Desired);
        
        (uint256 amount0Uni, uint256 amount1Uni, uint256 collateralAmount, uint256 shortDelta) = calcOptimalAmount(_args, sqrtPriceX96, tickCurrent, _args.shortLeverage);
        (_args.amount0Desired, _args.amount1Desired) = swapToOptimalAmount(_args.amount0Desired, _args.amount1Desired, amount0Uni, amount1Uni, collateralAmount, _args.feeTier);

        token0.approve(address(uniV3Manager), _args.amount0Desired);
        token1.approve(address(uniV3Manager), _args.amount1Desired);
        collateralToken.approve(address(gmxManager), collateralAmount);

        // Prepare protocol open arguments
        DerivioPositionManager.ProtocolOpenArg[] memory openArgs = new DerivioPositionManager.ProtocolOpenArg[](2);
        openArgs[0] = createUniV3ProtocolOpenArg(_args, sqrtPriceX96);
        openArgs[1] = createGmxProtocolOpenArg(_args.value, collateralAmount, shortDelta);

        // Open positions
        return derivioPositionManager.openProtocolsPosition{ value: _args.value }(_args.recipient, openArgs);
    }

    function createUniV3ProtocolOpenArg(PositionArgs memory _args, uint160 _sqrtPriceX96Current) 
        internal view 
        returns (DerivioPositionManager.ProtocolOpenArg memory uniV3Arg) 
    {
        uint160 sqrtPriceX96Lower = TickMath.getSqrtRatioAtTick(_args.tickLower);
        uint160 sqrtPriceX96Upper = TickMath.getSqrtRatioAtTick(_args.tickUpper);
        uint128 liquidityDesired = 
            LiquidityAmounts.getLiquidityForAmounts(_sqrtPriceX96Current, sqrtPriceX96Lower, sqrtPriceX96Upper, _args.amount0Desired, _args.amount1Desired);
        
        console.log('liquidityDesired:', liquidityDesired);
        console.log('_sqrtPriceX96Current:', _sqrtPriceX96Current);
        console.log('amount0Desired:', _args.amount0Desired);
        console.log('amount1Desired:', _args.amount1Desired);

        uniV3Arg = DerivioPositionManager.ProtocolOpenArg({
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

    function createGmxProtocolOpenArg(uint256 _value, uint256 _collateralAmount, uint256 _shortDelta) 
        internal view 
        returns (DerivioPositionManager.ProtocolOpenArg memory gmxArg) 
    {
        uint256 acceptPrice = 0;
        bool _isLong = false;

        gmxArg = DerivioPositionManager.ProtocolOpenArg({
            manager: gmxManager,
            value: _value,
            funds: new IProtocolPositionManager.Fund[](1),
            inputs: abi.encode(
                address(collateralToken),
                address(indexToken),
                _isLong,
                _collateralAmount,
                _shortDelta,
                acceptPrice
            )
        });

        gmxArg.funds[0].token = address(collateralToken);
        gmxArg.funds[0].amount = _collateralAmount;
    }

    function closePosition(address _account, DerivioACloseArgs memory _args)
        external payable nonReentrant 
        returns (DerivioPositionManager.ProtocolCloseResult[] memory closedPositions_)
    {
        DerivioPositionManager.ProtocolOpenResult[] memory position = derivioPositionManager.positionOf(_args.positionKey);
        DerivioPositionManager.ProtocolCloseArg[] memory protocolCloseArgs = new DerivioPositionManager.ProtocolCloseArg[](position.length);

        for (uint i = 0; i < position.length; i++) {
            if (position[i].manager == uniV3Manager) {
                protocolCloseArgs[i] = DerivioPositionManager.ProtocolCloseArg({
                    manager: uniV3Manager,
                    inputs: abi.encode(position[i].key),
                    value: 0
                });

            } else if (position[i].manager == gmxManager) {
                protocolCloseArgs[i] = DerivioPositionManager.ProtocolCloseArg({
                    manager: gmxManager,
                    inputs: abi.encode(position[i].key, uint256(0), type(uint256).max),
                    value: _args.value
                });
            }
        }

        // Call closeProtocolsPosition
        closedPositions_ = derivioPositionManager.closeProtocolsPosition{ value: _args.value }(_account, _args.positionKey, protocolCloseArgs);

        for (uint i = 0; i < closedPositions_.length; i++) {
            if (closedPositions_[i].manager == uniV3Manager) {
                
                uint256 collect0 = closedPositions_[i].funds[0].amount;
                uint256 collect1 = closedPositions_[i].funds[1].amount;

                if (_args.swapToCollateral) {
                    uint24 feeTier = 500;
                    (collect0, collect1) = swapToCollateral(collect0, collect1, feeTier);
                }
                
                // Return the funds to the account
                returnFund(_account, collect0, collect1);

            } else if (closedPositions_[i].manager == gmxManager) {
                // Handle GMX closed position if needed
            }
        }
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
        uint256 shortLeverage
    )
        public
        returns (uint256 amount0Uni, uint256 amount1Uni, uint256 amountCollateral, uint256 shortDelta)
    {
        uint256 amount0Total = _args.amount0Desired + uniHelper.amount1ToAmount0(_args.amount1Desired, _sqrtPriceX96);

        if (shortLeverage != 0) {
            require(shortLeverage >= shortDenominator, "shortLeverage too small");

            (uint256 amount0TotalSim, , , , uint256 amount0LowerSim, ) = uniHelper.ratioAtTick(_tickCurrent, _args.tickLower, _args.tickUpper, false);
            amountCollateral = amount0Total * amount0LowerSim / amount0TotalSim;

            // apply leverage
            shortDelta = amountCollateral;
            amountCollateral = amountCollateral * shortDenominator / shortLeverage;

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

    function returnFund(address _account, uint256 _amount0, uint256 _amount1) 
        internal 
    {
        token0.safeTransfer(_account, _amount0);
        token1.safeTransfer(_account, _amount1);
    }
}