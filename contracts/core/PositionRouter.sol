// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interface/uniswap/INonfungiblePositionManager.sol";
import "../interface/gmx/IGmxPositionRouter.sol";
import "./interface/IDerivioPositionManager.sol";
import "./DerivioA.sol";
import "./OrderManager.sol";
import "../peripherals/UniHelper.sol";
import "../protocols-manager/GmxManager.sol";
import "../protocols-manager/UniV3Manager.sol";
import "./DerivioAFactory.sol";
import "hardhat/console.sol";

contract PositionRouter is ReentrancyGuard {

    using SafeERC20 for IERC20;
    
    DerivioAFactory derivioAFactory;
    UniHelper uniHelper;
    IUniswapV3Factory uniFactory;
    ISwapRouter swapRouter;
    IDerivioPositionManager derivioPositionManager;
    OrderManager orderManager;
    UniV3Manager uniV3Manager;
    GmxManager gmxManager;
    uint32 immutable derivioAId = 0;
    uint32 immutable derivioFutureId = 1;
    
    constructor (
        DerivioAFactory _derivioAFactory, 
        UniHelper _uniHelper, 
        IUniswapV3Factory _uniFactory,
        ISwapRouter _swapRouter,
        IDerivioPositionManager _derivioPositionManager,
        OrderManager _orderManager,
        UniV3Manager _uniV3Manager,
        GmxManager _gmxManager
        ) 
    {
        derivioAFactory = _derivioAFactory;
        uniHelper = _uniHelper;
        uniFactory = _uniFactory;
        swapRouter = _swapRouter;
        derivioPositionManager = _derivioPositionManager;
        orderManager = _orderManager;
        uniV3Manager = _uniV3Manager;
        gmxManager = _gmxManager;
    }

    function addDerivioAPair(
        address _token0,
        address _token1,
        bool _isZeroCollateral
    ) 
        public
    {
        (_token0, _token1) = uniHelper.getTokenOrder(_token0, _token1);

        derivioAFactory.addPair(derivioAFactory.getPairId(derivioAId, _token0, _token1), new DerivioA(
            msg.sender,
            uniHelper,
            uniFactory,
            swapRouter,
            derivioPositionManager,
            orderManager,
            uniV3Manager,
            gmxManager,
            _token0, 
            _token1,
            _isZeroCollateral
        ));
    }

    function addDerivioFuturePair(
        address _collateralToken,
        address _indexToken
    ) 
        public
    {
        derivioAFactory.addFuturePair(derivioAFactory.getFuturePairId(derivioFutureId, _collateralToken, _indexToken), new DerivioFuture(
            derivioPositionManager,
            gmxManager,
            _collateralToken, 
            _indexToken
        ));
    }
    
    function openDerivioAPositions(DerivioA.OpenArgs[] memory _argsList, address _token0, address _token1)
        payable external nonReentrant
        returns (IDerivioPositionManager.OpenInfo[] memory)
    {
        DerivioA derivioA = getDerivioAContract(derivioAId, _token0, _token1);
        uint256 keeperFee = orderManager.keeperFeeOf(derivioAId);
        IDerivioPositionManager.OpenInfo[] memory results = new IDerivioPositionManager.OpenInfo[](_argsList.length);

        for (uint i = 0; i < _argsList.length; i++) {
            results[i] = openDerivioA(derivioA, IERC20(_token0), IERC20(_token1), _argsList[i], keeperFee);
        }

        return results;
    }

    function openDerivioA(DerivioA _derivioA, IERC20 _token0, IERC20 _token1, DerivioA.OpenArgs memory _args, uint256 _keeperFee)
        internal
        returns (IDerivioPositionManager.OpenInfo memory)
    {
        if (_args.transferFromRecipient) {
            _token0.safeTransferFrom(_args.recipient, address(this), _args.amount0Desired);
            _token1.safeTransferFrom(_args.recipient, address(this), _args.amount1Desired);
        }
        else {
            _token0.safeTransferFrom(msg.sender, address(this), _args.amount0Desired);
            _token1.safeTransferFrom(msg.sender, address(this), _args.amount1Desired);
        }
        
        _token0.approve(address(_derivioA), _args.amount0Desired);
        _token1.approve(address(_derivioA), _args.amount1Desired);

        if (_args.shortLeverage == 0) {
            return _derivioA.openAS(_args);
        } else {
            orderManager.receiveKeeperFee{ value: _keeperFee }(derivioAId);
            return _derivioA.openAL{ value: gmxManager.minExecutionFee() }(_args);
        }
    }
    
    function openDerivioFuturePositions(DerivioFuture.OpenArgs[] memory _argsList, address _collateralToken, address _indexToken)
        payable external nonReentrant
        returns (IDerivioPositionManager.OpenInfo[] memory)
    {
        DerivioFuture derivioFuture = getDerivioFutureContract(derivioFutureId, _collateralToken, _indexToken);
        IDerivioPositionManager.OpenInfo[] memory results = new IDerivioPositionManager.OpenInfo[](_argsList.length);
        uint256 keeperFee = orderManager.keeperFeeOf(derivioFutureId); 

        for (uint i = 0; i < _argsList.length; i++) {
            results[i] = openDerivioFuture(derivioFuture, IERC20(_collateralToken), _argsList[i], keeperFee);
        }

        orderManager.receiveKeeperFee{ value: keeperFee * _argsList.length }(derivioFutureId);

        return results;
    }

    function openDerivioFuture(DerivioFuture _derivioFuture, IERC20 _collateralToken, DerivioFuture.OpenArgs memory _args, uint256 _keeperFee)
        internal
        returns (IDerivioPositionManager.OpenInfo memory)
    {
        if (_args.transferFromRecipient) {
            _collateralToken.safeTransferFrom(_args.recipient, address(this), _args.collateralAmount);
        }
        else {
            _collateralToken.safeTransferFrom(msg.sender, address(this), _args.collateralAmount);
        }

        _collateralToken.approve(address(_derivioFuture), _args.collateralAmount);

        return _derivioFuture.openFuture{ value: gmxManager.minExecutionFee() }(_args, _keeperFee);
    }

    function closeDerivioPosition(DerivioA.CloaseArgs[] memory _argsList, address _token0, address _token1) 
        external payable nonReentrant 
        returns (IDerivioPositionManager.CloseResult[][] memory)
    {
        DerivioA derivioA = getDerivioAContract(derivioAId, _token0, _token1);
        IDerivioPositionManager.CloseResult[][] memory results = new IDerivioPositionManager.CloseResult[][](_argsList.length);
        uint256 sumKeeperFee = 0;

        for (uint i = 0; i < _argsList.length; i++) {
            sumKeeperFee += derivioPositionManager.keeperFee(_argsList[i].positionKey);
            results[i] = derivioA.closePosition{ value: getCloseExecutionFee(_argsList[i].positionKey) }(msg.sender, _argsList[i]);
        }

        orderManager.transferOutETH(sumKeeperFee, payable(msg.sender));

        return results;
    }

    // function closeDerivioFuture(DerivioFuture.CloseArgs[] memory _argsList, address _collateralToken, address _indexToken) 
    //     external payable nonReentrant 
    //     returns (IDerivioPositionManager.CloseResult[][] memory)
    // {
    //     DerivioFuture derivioFuture = getDerivioFutureContract(derivioFutureId, _collateralToken, _indexToken);
    //     IDerivioPositionManager.CloseResult[][] memory results = new IDerivioPositionManager.CloseResult[][](_argsList.length);
    //     uint256 sumKeeperFee = 0;

    //     for (uint i = 0; i < _argsList.length; i++) {
    //         sumKeeperFee += derivioPositionManager.keeperFee(_argsList[i].positionKey);
    //         results[i] = derivioFuture.closeFuture{ value: gmxManager.minExecutionFee() }(msg.sender, _argsList[i]);
    //     }

    //     orderManager.transferOutETH(sumKeeperFee, payable(msg.sender));

    //     return results;
    // }

    function claimFees(bytes32[] memory _positionKeys)
        public
    {
        for (uint i = 0; i < _positionKeys.length; i++) {
            derivioPositionManager.claimFees(msg.sender, _positionKeys[i]);
        }
    }

    function getDerivioAContract(uint32 _derivioId, address _token0, address _token1) 
        public view returns (DerivioA) 
    {
        return DerivioA(derivioAFactory.getAddress(derivioAFactory.getPairId(_derivioId, _token0, _token1)));
    }

    function getDerivioFutureContract(uint32 _derivioId, address _collateralToken, address _indexToken) 
        public view returns (DerivioFuture) 
    {
        return DerivioFuture(derivioAFactory.getFutureAddress(derivioAFactory.getFuturePairId(_derivioId, _collateralToken, _indexToken)));
    }

    function getCloseExecutionFee(bytes32 _positionKey) 
        internal view
        returns (uint256)
    {
        IDerivioPositionManager.OpenInfo memory openInfo = derivioPositionManager.positionOf(_positionKey);

        for (uint i = 0; i < openInfo.openResults.length; i++) {
            if (openInfo.openResults[i].manager == gmxManager) { 
                return gmxManager.minExecutionFee();
            }
        }

        return 0;
    }

    // function positionsOf(address _account) 
    //     public view returns (DerivioPositionManager.Pos[] memory) 
    // {
    //     return derivioPositionManager.getAllPositions(_account);
    // }
}