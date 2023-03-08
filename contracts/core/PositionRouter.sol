// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;


import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../peripherals/UniHelper.sol";
import "./DerivioA.sol";
import "./DerivioAStorage.sol";
import "hardhat/console.sol";

contract PositionRouter is ReentrancyGuard {

    DerivioAStorage public derivioAStorage;
    uint32 DerivioAId = 0;

    constructor (DerivioAStorage _derivioAStorage) 
    {
        derivioAStorage = _derivioAStorage;
    }

    function addDerivioAPair(
        UniHelper _uniHelper, 
        IUniswapV3Factory _uniFactory, 
        ISwapRouter _swapRouter,
        INonfungiblePositionManager _positionManager,
        address _token0,
        address _token1
    ) 
        public
    {
        (address token0, address token1) = _uniHelper.getTokenOrder(_token0, _token1);
        bytes32 pairId = getPairId(DerivioAId, token0, token1);

        DerivioA newDerivioA = new DerivioA(
            _uniHelper,
            _uniFactory,
            _swapRouter,
            _positionManager,
            token0, 
            token1
        );
        derivioAStorage.addPair(pairId, newDerivioA);
    }

    function getPairId(
        uint32 _derivioId,
        address _token0,
        address _token1
    ) public pure returns (bytes32 pairId) {
        return keccak256(abi.encodePacked(_derivioId, _token0, _token1));
    }
}