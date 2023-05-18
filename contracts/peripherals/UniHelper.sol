// SPDX-License-Identifier: GPL-2.0
pragma solidity 0.8.13;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FullMath, LiquidityAmounts } from "@arrakisfi/v3-lib-0.8/contracts/LiquidityAmounts.sol";
import { TickMath } from "@arrakisfi/v3-lib-0.8/contracts/TickMath.sol";
import { FixedPoint96 } from "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "hardhat/console.sol";

contract UniHelper {

    uint128 private constant precision = 1e10;
    IUniswapV3Factory public immutable uniFactory;
    uint256 private constant SCALING_FACTOR = 2 ** 96;

    constructor (IUniswapV3Factory _uniFactory) 
    {
        uniFactory = _uniFactory;
    }

    function validateTickSpacing(
        IUniswapV3Pool _pool, 
        int24 _tickLower, 
        int24 _tickUpper
    )
        public
        view
    {
        int24 spacing = _pool.tickSpacing();
        require(_tickLower < _tickUpper &&
            _tickLower % spacing == 0 &&
            _tickUpper % spacing == 0,
            "tick should be at interval spacing");
    }

    function getTokenOrder(address _tokenA, address _tokenB)
        public
        pure
        returns (address token0, address token1)
    {
        require(_tokenA != _tokenB, "same token");
        (token0, token1) = _tokenA < _tokenB
            ? (_tokenA, _tokenB)
            : (_tokenB, _tokenA);
    }

    function ratioAtTick(
        int24 _tickCurrent, 
        int24 _tickLower, 
        int24 _tickUpper,
        bool _isFlipped
    ) 
        external
        returns (
            uint256 amount0Total, 
            uint256 amount1Total, 
            uint256 amount0Current, 
            uint256 amount1Current, 
            uint256 amountLower,
            uint256 amountUpper
            ) 
    {
        uint160 sqrtPriceX96Current = TickMath.getSqrtRatioAtTick(_tickCurrent);
        uint160 sqrtPriceX96Lower = TickMath.getSqrtRatioAtTick(_tickLower);
        uint160 sqrtPriceX96Upper = TickMath.getSqrtRatioAtTick(_tickUpper);
        
        (amount0Current, amount1Current) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96Current,
                sqrtPriceX96Lower,
                sqrtPriceX96Upper,
                precision
            );
        
        (amountLower, ) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96Lower,
                sqrtPriceX96Lower,
                sqrtPriceX96Upper,
                precision
            );

        (, amountUpper) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96Upper,
                sqrtPriceX96Lower,
                sqrtPriceX96Upper,
                precision
            );

        amount0Total = amount0Current + amount1ToAmount0(amount1Current, sqrtPriceX96Current) + amountLower;
        amount1Total = amount1Current + amount0ToAmount1(amount0Current, sqrtPriceX96Current) + amountUpper;
    }

    function calcAmountRatio(
        int24 _tickCurrent, 
        int24 _tickLower, 
        int24 _tickUpper
    ) 
        pure
        external
        returns (uint256 amount0, uint256 amount1, uint128 liquidity) 
    {
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                TickMath.getSqrtRatioAtTick(_tickCurrent),
                TickMath.getSqrtRatioAtTick(_tickLower),
                TickMath.getSqrtRatioAtTick(_tickUpper),
                precision
            );
        
        liquidity = precision;
    }

    function amount0ToAmount1(uint256 amount0, uint160 sqrtPriceX96) 
        public pure 
        returns (uint256 amount1)
    {
        if (sqrtPriceX96 == 0 || amount0 == 0) return 0;
        amount1 = (( (amount0 * uint256(sqrtPriceX96)) >> 96) * uint256(sqrtPriceX96)) >> 96;
        if (amount1 > 0) amount1--;
    }

    // function amount1ToAmount0(uint256 amount1, uint160 sqrtPriceX96) 
    //     public pure 
    //     returns (uint256 amount0)
    // {
    //     if (sqrtPriceX96 == 0 || amount1 == 0) return 0;
    //     amount0 = FullMath.mulDiv(FullMath.mulDiv(amount1, 1 << 96, sqrtPriceX96), 1 << 96, sqrtPriceX96);
    // }

    // function amount0ToAmount1(uint256 amount0, uint160 sqrtPriceX96)
    //     public pure
    //     returns (uint256 amount1)
    // {
    //     if (sqrtPriceX96 == 0 || amount0 == 0) return 0;
    //     uint256 scaledSqrtPrice = sqrtPriceX96 * 1e18 / SCALING_FACTOR;
    //     amount1 = (amount0 * scaledSqrtPrice * scaledSqrtPrice) / 1e18;
    //     if (amount1 > 0) amount1--;
    // }

    function amount1ToAmount0(uint256 amount1, uint160 sqrtPriceX96)
        public pure
        returns (uint256 amount0)
    {
        if (sqrtPriceX96 == 0 || amount1 == 0) return 0;
        uint256 scaledSqrtPrice = sqrtPriceX96 * 1e18 / SCALING_FACTOR;
        amount0 = (amount1 * 1e36) / (scaledSqrtPrice * scaledSqrtPrice);
    }

    function sqrtPriceX96ToPrice(uint160 sqrtPriceX96) public pure returns (uint256) {
        return uint256(sqrtPriceX96) * uint256(sqrtPriceX96) / 2 ** 192;
    }
}