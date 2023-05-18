// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interface/uniswap/INonfungiblePositionManager.sol";
import "../interface/gmx/IGmxPositionRouter.sol";
import "./interface/IDerivioPositionManager.sol";
import "./DerivioA.sol";
import "../peripherals/UniHelper.sol";
import "../protocols-manager/GmxManager.sol";
import "../protocols-manager/UniV3Manager.sol";
import "./DerivioAFactory.sol";
import "hardhat/console.sol";

contract PositionRouter is ReentrancyGuard {

    using SafeERC20 for IERC20;
    
    DerivioAFactory derivioAFactory;
    IDerivioPositionManager derivioPositionManager;
    uint32 immutable derivioAId = 0;
    uint32 immutable derivioFutureId = 1;
    
    constructor (DerivioAFactory _derivioAFactory, IDerivioPositionManager _derivioPositionManager) 
    {
        derivioAFactory = _derivioAFactory;
        derivioPositionManager = _derivioPositionManager;
    }

    function addDerivioAPair(
        UniHelper _uniHelper, 
        IUniswapV3Factory _uniFactory, 
        ISwapRouter _swapRouter,
        IDerivioPositionManager _derivioPositionManager,
        UniV3Manager _uniV3Manager,
        GmxManager _gmxManager,
        address _token0,
        address _token1,
        bool _isZeroCollateral
    ) 
        public
    {
        (_token0, _token1) = _uniHelper.getTokenOrder(_token0, _token1);

        derivioAFactory.addPair(derivioAFactory.getPairId(derivioAId, _token0, _token1), new DerivioA(
            _uniHelper,
            _uniFactory,
            _swapRouter,
            _derivioPositionManager,
            _uniV3Manager,
            _gmxManager,
            _token0, 
            _token1,
            _isZeroCollateral
        ));
    }

    function addDerivioFuturePair(
        IDerivioPositionManager _derivioPositionManager,
        GmxManager _gmxManager,
        address _collateralToken,
        address _indexToken
    ) 
        public
    {
        derivioAFactory.addFuturePair(derivioAFactory.getFuturePairId(derivioFutureId, _collateralToken, _indexToken), new DerivioFuture(
            _derivioPositionManager,
            _gmxManager,
            _collateralToken, 
            _indexToken
        ));
    }
    
    function openDerivioAPositions(DerivioA.OpenArgs[] memory _argsList, address _token0, address _token1)
        payable external nonReentrant
        returns (IDerivioPositionManager.ProtocolOpenResult[][] memory)
    {
        DerivioA derivioA = getDerivioAContract(derivioAId, _token0, _token1);
        IDerivioPositionManager.ProtocolOpenResult[][] memory results = new IDerivioPositionManager.ProtocolOpenResult[][](_argsList.length);

        uint256 sumValue = 0;
        for (uint i = 0; i < _argsList.length; i++) {
            sumValue += _argsList[i].value;
        }
        require(msg.value == sumValue, "val error");

        for (uint i = 0; i < _argsList.length; i++) {
            results[i] = openDerivioA(derivioA, IERC20(_token0), IERC20(_token1), _argsList[i]);
        }

        return results;
    }

    function openDerivioA(DerivioA _derivioA, IERC20 _token0, IERC20 _token1, DerivioA.OpenArgs memory _args)
        internal
        returns (IDerivioPositionManager.ProtocolOpenResult[] memory)
    {
        _token0.safeTransferFrom(msg.sender, address(this), _args.amount0Desired);
        _token1.safeTransferFrom(msg.sender, address(this), _args.amount1Desired);

        _token0.approve(address(_derivioA), _args.amount0Desired);
        _token1.approve(address(_derivioA), _args.amount1Desired);

        if (_args.shortLeverage == 0) {
            return _derivioA.openAS(_args);
        } else {
            return _derivioA.openAL{ value: _args.value }(_args);
        }
    }
    
    function openDerivioFuturePositions(DerivioFuture.OpenArgs[] memory _argsList, address _collateralToken, address _indexToken)
        payable external nonReentrant
        returns (IDerivioPositionManager.ProtocolOpenResult[][] memory)
    {
        DerivioFuture derivioFuture = getDerivioFutureContract(derivioFutureId, _collateralToken, _indexToken);
        IDerivioPositionManager.ProtocolOpenResult[][] memory results = new IDerivioPositionManager.ProtocolOpenResult[][](_argsList.length);

        for (uint i = 0; i < _argsList.length; i++) {
            results[i] = openDerivioFuture(derivioFuture, IERC20(_collateralToken), _argsList[i]);
        }

        return results;
    }

    function openDerivioFuture(DerivioFuture _derivioFuture, IERC20 _collateralToken, DerivioFuture.OpenArgs memory _args)
        internal
        returns (IDerivioPositionManager.ProtocolOpenResult[] memory)
    {
        _collateralToken.safeTransferFrom(msg.sender, address(this), _args.collateralAmount);
        _collateralToken.approve(address(_derivioFuture), _args.collateralAmount);

        return _derivioFuture.openFuture{ value: _args.value }(_args);
    }

    function closeDerivioA(DerivioA.CloaseArgs[] memory _argsList, address _token0, address _token1) 
        external payable nonReentrant 
        returns (IDerivioPositionManager.ProtocolCloseResult[][] memory)
    {
        DerivioA derivioA = getDerivioAContract(derivioAId, _token0, _token1);
        IDerivioPositionManager.ProtocolCloseResult[][] memory results = new IDerivioPositionManager.ProtocolCloseResult[][](_argsList.length);

        for (uint i = 0; i < _argsList.length; i++) {
            results[i] = derivioA.closePosition{ value: _argsList[i].value }(msg.sender, _argsList[i]);
        }

        return results;
    }

    function closeDerivioFuture(DerivioFuture.CloseArgs[] memory _argsList, address _collateralToken, address _indexToken) 
        external payable nonReentrant 
        returns (IDerivioPositionManager.ProtocolCloseResult[][] memory)
    {
        DerivioFuture derivioFuture = getDerivioFutureContract(derivioFutureId, _collateralToken, _indexToken);
        IDerivioPositionManager.ProtocolCloseResult[][] memory results = new IDerivioPositionManager.ProtocolCloseResult[][](_argsList.length);

        for (uint i = 0; i < _argsList.length; i++) {
            results[i] = derivioFuture.closeFuture{ value: _argsList[i].value }(msg.sender, _argsList[i]);
        }

        return results;
    }

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

    // function positionsOf(address _account) 
    //     public view returns (DerivioPositionManager.Pos[] memory) 
    // {
    //     return derivioPositionManager.getAllPositions(_account);
    // }
}