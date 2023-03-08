// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FullMath, LiquidityAmounts } from "@arrakisfi/v3-lib-0.8/contracts/LiquidityAmounts.sol";
import { TickMath } from "@arrakisfi/v3-lib-0.8/contracts/TickMath.sol";
import {FixedPoint96} from "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "hardhat/console.sol";

contract UniHelper {

    uint128 private constant precision = 1e10;
    IUniswapV3Factory public immutable uniFactory;

    constructor (IUniswapV3Factory _uniFactory) 
    {
        uniFactory = _uniFactory;
    }

    function validateTickSpacing(
        address _pool, 
        int24 _tickLower, 
        int24 _tickUpper
    )
        public
        view
    {
        int24 spacing = IUniswapV3Pool(_pool).tickSpacing();
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

    function calcAmountRatio(
        int24 _tickCurrent, 
        int24 _tickLower, 
        int24 _tickUpper
    ) 
        pure
        external
        returns (uint256 amount0, uint256 amount1) 
    {
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                TickMath.getSqrtRatioAtTick(_tickCurrent),
                TickMath.getSqrtRatioAtTick(_tickLower),
                TickMath.getSqrtRatioAtTick(_tickUpper),
                precision
            );
    }
}