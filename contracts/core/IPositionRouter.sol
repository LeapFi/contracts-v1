// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "../interface/gmx/IGmxPositionRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPositionRouter {
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
        FeeGrowthData feeGrowthData;
    }

    struct FeeGrowthData {
        uint256 feeGrowthInside0X128;
        uint256 feeGrowthInside1X128;
        uint256 feeGrowthLast0X128;
        uint256 feeGrowthLast1X128;
    }

    struct GmxPosition {
        address minVault;
        uint256 collateralAmount;
        uint256 shortDelta;
    }

    function openDerivioA(PositionArgs memory _args, address _token0, address _token1) external payable;
    function closeDerivioA(bytes32[] memory _positionKeys, address _token0, address _token1) external payable;
    function positionsOf(address _account) external view returns (ComposedLiquidity[] memory);
    
    function getPairId(uint32 _derivioId, address _token0, address _token1) external pure returns (bytes32 pairId);
    function getDerivioAddress(uint32 _derivioId, address _token0, address _token1) external view returns (address);
}
