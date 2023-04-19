// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interface/uniswap/INonfungiblePositionManager.sol";
import "../interface/gmx/IGmxPositionRouter.sol";
import "../peripherals/UniHelper.sol";
import "../protocols-manager/GmxManager.sol";
import "../protocols-manager/UniV3Vault.sol";
import "./DerivioPositionManager.sol";
import "./DerivioA.sol";
import "./DerivioAStorage.sol";
import "hardhat/console.sol";

contract PositionRouter is ReentrancyGuard {

    using SafeERC20 for IERC20;
    
    DerivioAStorage derivioAStorage;
    DerivioPositionManager derivioPositionManager;
    uint32 derivioAId = 0;
    
    constructor (DerivioAStorage _derivioAStorage, DerivioPositionManager _derivioPositionManager) 
    {
        derivioAStorage = _derivioAStorage;
        derivioPositionManager = _derivioPositionManager;
    }

    function addDerivioAPair(
        UniHelper _uniHelper, 
        IUniswapV3Factory _uniFactory, 
        ISwapRouter _swapRouter,
        DerivioPositionManager _derivioPositionManager,
        UniV3Vault _uniV3Vault,
        GmxManager _gmxManager,
        address _token0,
        address _token1,
        bool _isZeroCollateral
    ) 
        public
    {
        (address token0, address token1) = _uniHelper.getTokenOrder(_token0, _token1);

        derivioAStorage.addPair(getPairId(derivioAId, token0, token1), new DerivioA(
            _uniHelper,
            _uniFactory,
            _swapRouter,
            _derivioPositionManager,
            _uniV3Vault,
            _gmxManager,
            token0, 
            token1,
            _isZeroCollateral
        ));
    }

    function openDerivioA(DerivioA.PositionArgs memory _args, address _token0, address _token1)
        payable
        external
        nonReentrant
    {
        bytes32 pairId = getPairId(derivioAId, _token0, _token1);
        address contractAddr = derivioAStorage.getAddress(pairId);

        IERC20(_token0).safeTransferFrom(msg.sender, address(this), _args.amount0Desired);
        IERC20(_token1).safeTransferFrom(msg.sender, address(this), _args.amount1Desired);

        IERC20(_token0).approve(contractAddr, _args.amount0Desired);
        IERC20(_token1).approve(contractAddr, _args.amount1Desired);

        if (_args.shortLeverage == 0) {
            DerivioA(contractAddr).openAS(_args);
        }
        else {
            DerivioA(contractAddr).openAL{ value: msg.value }(_args);
        }
    }

    function closeDerivioA(bytes32[] memory _positionKeys, bool _swapToCollateral, address _token0, address _token1) 
            external payable nonReentrant 
    {
        bytes32 pairId = getPairId(derivioAId, _token0, _token1);
        address contractAddr = derivioAStorage.getAddress(pairId);

        for (uint i = 0; i < _positionKeys.length; i++) {
            DerivioA(contractAddr).closePosition{ value: msg.value }(msg.sender, _positionKeys[i], _swapToCollateral);
        }
    }

    function getPairId(
        uint32 _derivioId,
        address _token0,
        address _token1
    ) public pure returns (bytes32 pairId) {
        return keccak256(abi.encodePacked(_derivioId, _token0, _token1));
    }

    function getDerivioAddress(
        uint32 _derivioId,
        address _token0,
        address _token1
    ) public view returns (address) {
        return derivioAStorage.getAddress(getPairId(_derivioId, _token0, _token1));
    }

    // function positionsOf(address _account) 
    //     public view returns (DerivioPositionManager.Pos[] memory) 
    // {
    //     return derivioPositionManager.getAllPositions(_account);
    // }

    function getGmxPosition(address _token0, address _token1) 
        public view
        returns (uint256 sizeDelta, uint256 collateral)
    {
        bytes32 pairId = getPairId(derivioAId, _token0, _token1);
        address contractAddr = derivioAStorage.getAddress(pairId);
        (sizeDelta, collateral) = DerivioA(contractAddr).getGmxPosition();
    }
}