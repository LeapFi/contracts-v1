// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;


import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "../interface/gmx/IGmxPositionRouter.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../peripherals/UniHelper.sol";
import "./DerivioA.sol";
import "./DerivioAStorage.sol";
import "hardhat/console.sol";

contract PositionRouter is ReentrancyGuard {

    DerivioAStorage public derivioAStorage;
    uint32 derivioAId = 0;
    
    struct UniV3Params {
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
        uint24 feeTier;
        int24 tickLower;
        int24 tickUpper;
        uint160 sqrtPriceLimitX96;
    }

    struct GmxParams {
        uint256 depositedUsdc;
        uint256 shortDelta;
        uint160 sqrtPriceLimitX96;
    }

    constructor (DerivioAStorage _derivioAStorage) 
    {
        derivioAStorage = _derivioAStorage;
    }

    function addDerivioAPair(
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
        public
    {
        (address token0, address token1) = _uniHelper.getTokenOrder(_token0, _token1);
        bytes32 pairId = getPairId(derivioAId, token0, token1);

        derivioAStorage.addPair(pairId, new DerivioA(
            _uniHelper,
            _uniFactory,
            _swapRouter,
            _positionManager,
            _gmxPositionRouter,
            _gmxRouter,
            _gmxVault,
            token0, 
            token1,
            _isZeroCollateral
        ));
    }

    function openDerivioA(DerivioA.PositionArgs memory args, address _token0, address _token1)
        external
        nonReentrant
    {
        bytes32 pairId = getPairId(derivioAId, _token0, _token1);
        address contractAddr = derivioAStorage.getAddress(pairId);
        
        DerivioA(contractAddr).openPosition(args);
    }

    function getPairId(
        uint32 _derivioId,
        address _token0,
        address _token1
    ) public pure returns (bytes32 pairId) {
        return keccak256(abi.encodePacked(_derivioId, _token0, _token1));
    }
}