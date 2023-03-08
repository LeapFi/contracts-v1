// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FullMath, LiquidityAmounts } from "@arrakisfi/v3-lib-0.8/contracts/LiquidityAmounts.sol";
import { TickMath } from "@arrakisfi/v3-lib-0.8/contracts/TickMath.sol";
import "../peripherals/UniHelper.sol";
import "hardhat/console.sol";

contract DerivioA is ReentrancyGuard {

    using SafeERC20 for IERC20;
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    uint128 private constant precision = 1e10;

    UniHelper private immutable uniHelper;
    IUniswapV3Factory private immutable uniFactory;
    ISwapRouter private immutable swapRouter;
    INonfungiblePositionManager private immutable positionManager;

    // user address => composed liqudity positions
    mapping(address => ComposedLiquidity[]) public composedLiquidity;

    struct ComposedLiquidity {
        uint256 openTime;
        UniV3Position uniV3Position;
        GMXPosition gmxPosition;
    }

    struct UniV3Position {
        int24 tickLower;
        int24 tickUpper;
        uint24 feeTier;
        uint256 tokenId;
        uint128 liquidity;
    }

    struct GMXPosition {
        uint256 id;
        uint256 depositedUsdc;
        uint128 shortDelta;
    }

    constructor (
        UniHelper _uniHelper, 
        IUniswapV3Factory _uniFactory, 
        ISwapRouter _swapRouter,
        INonfungiblePositionManager _positionManager,
        address _token0,
        address _token1
        ) 
    {
        uniHelper = _uniHelper;
        uniFactory = _uniFactory;
        swapRouter = _swapRouter;
        positionManager = _positionManager;
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    function openPosition(
        address _recipient,
        int24 _tickLower, 
        int24 _tickUpper, 
        uint24 _feeTier, 
        uint256 _amount0Desired, 
        uint256 _amount1Desired, 
        uint24 _shortRatio
    )
        external
        nonReentrant
    {
        _amount0Desired = 0;
        _shortRatio = 0;
        address poolAddress = uniFactory.getPool(
                        address(token0),
                        address(token1),
                        _feeTier
                    );
        uniHelper.validateTickSpacing(poolAddress, _tickLower, _tickUpper);

        token0.safeTransferFrom(msg.sender, address(this), _amount0Desired);
        token1.safeTransferFrom(msg.sender, address(this), _amount1Desired);

        (, int24 tickCurrent, , , , , ) = IUniswapV3Pool(poolAddress).slot0();
        // (uint256 amount0Ratio, uint256 amount1Ratio) = uniHelper.calcAmountRatio(tickCurrent, _tickLower, _tickUpper);

        // console.log("ratio..");
        // console.log("amount0Ratio: %s", amount0Ratio);
        // console.log("amount1Ratio: %s", amount1Ratio);

        uint256 amount1Swap = (_amount1Desired * precision - 
            _amount1Desired * precision * uint256(int256(tickCurrent - _tickLower)) / uint256(int256(_tickUpper - _tickLower))) / precision;
        
        _amount1Desired -= amount1Swap;
        _amount0Desired += swapExactInputSingle(token1, token0, amount1Swap, _feeTier);
        
        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0Minted,
            uint256 amount1Minted ) = mintLiquidity(_tickLower, _tickUpper, _feeTier, _amount0Desired, _amount1Desired);

        _amount0Desired -= amount0Minted;
        _amount1Desired -= amount1Minted;

        console.log("remains..");
        console.log("amount0Owed: %s", _amount0Desired);
        console.log("amount1Owed: %s", _amount1Desired);

        if (_amount0Desired != 0)
            token0.safeTransfer(msg.sender, _amount0Desired);

        if (_amount1Desired != 0)
            token1.safeTransfer(msg.sender, _amount1Desired);

        addPositionInfo(_recipient, _tickLower, _tickUpper, _feeTier, tokenId, liquidity, 0);
        // console.log("liquidity: %s", liquidity);
        // addPositionInfo(_tickLower, _tickUpper, _feeTier, liquidity, 0);

        console.log("balances..");
        console.log("amount0: %s", token0.balanceOf(address(this)));
        console.log("amount1: %s", token1.balanceOf(address(this)));
    }

    function addPositionInfo(
        address _recipient,
        int24 _tickLower, 
        int24 _tickUpper,
        uint24 _feeTier,
        uint256 _tokenId,
        uint128 _liquidity,
        uint128 _shortDelta
    )
        internal
    {
        ComposedLiquidity memory position;

        UniV3Position memory uniV3Position;
        uniV3Position.tickLower = _tickLower;
        uniV3Position.tickUpper = _tickUpper;
        uniV3Position.feeTier = _feeTier;
        uniV3Position.tokenId = _tokenId;
        uniV3Position.liquidity = _liquidity;

        GMXPosition memory gmxPosition;
        gmxPosition.id = 0;
        gmxPosition.depositedUsdc = 0;
        gmxPosition.shortDelta = 0;

        position.openTime = block.timestamp;
        position.uniV3Position = uniV3Position;
        position.gmxPosition = gmxPosition;

        composedLiquidity[_recipient].push(position);
    }

    function positionsOf(
        address _user
    )
        public
        view
        returns (ComposedLiquidity[] memory)
    {
        return composedLiquidity[_user];
    }

    function mintLiquidity(
        int24 _tickLower, 
        int24 _tickUpper, 
        uint24 _feeTier,
        uint256 _amount0, 
        uint256 _amount1
        ) 
        internal 
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0Minted,
            uint256 amount1Minted)
    {
        require(_amount0 > 0 && _amount1 > 0, "Amounts must be greater than zero");

        // Approve the Uniswap V3 contract to spend the tokens on behalf of this contract
        token0.approve(address(positionManager), _amount0);
        token1.approve(address(positionManager), _amount1);

        console.log("desired..");
        console.log("_amount0: %s", _amount0);
        console.log("_amount1: %s", _amount1);

        // Mint the position
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: _feeTier,
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            amount0Desired: _amount0,
            amount1Desired: _amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });
        (
            tokenId,
            liquidity,
            amount0Minted,
            amount1Minted
        ) = positionManager.mint(params);

        console.log("minting..");
        console.log("amount0Minted: %s", amount0Minted);
        console.log("amount1Minted: %s", amount1Minted);
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
}