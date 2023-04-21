// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interface/gmx/IGmxPositionRouter.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interface/gmx/IGmxRouter.sol";
import "../interface/gmx/IGmxVault.sol";
import "hardhat/console.sol";

contract MimGmxPosition is ReentrancyGuard {

    using SafeERC20 for IERC20;
    
    address account;
    address collateralToken;
    address indexToken;
    address[] path = new address[](1);
    bool isLong = false;
    uint256 private constant gmxDecimals = 30;

    IGmxPositionRouter private immutable gmxPositionRouter;
    IGmxRouter private immutable gmxRouter;
    IGmxVault private immutable gmxVault;

    constructor (
        address _account,
        IGmxPositionRouter _gmxPositionRouter,
        IGmxRouter _gmxRouter,
        IGmxVault _gmxVault,
        address _collateralToken,
        address _indexToken
        ) 
    {
        account = _account;
        gmxPositionRouter = _gmxPositionRouter;
        gmxRouter = _gmxRouter;
        gmxVault = _gmxVault;
        collateralToken = _collateralToken;
        indexToken = _indexToken;

        _gmxRouter.approvePlugin(address(_gmxPositionRouter));
        path[0] = collateralToken;
    }

    function openGmxShort(
        uint256 _collateralAmount,
        uint256 _sizeDelta,
        uint256 _acceptPrice
    ) 
        payable
        external
    {
        IERC20(collateralToken).approve(address(gmxRouter), _collateralAmount);
        bytes32 referralCode = 0;

        gmxPositionRouter.createIncreasePosition{ value: msg.value }(
            path, 
            indexToken, 
            _collateralAmount,
            0,
            _sizeDelta, 
            isLong, 
            _acceptPrice, 
            2e16,
            referralCode,
            address(0)
        );

        getGmxPosition();
    }

    function closeGmxShort(address _recipient, uint256 _minOut, uint256 _acceptablePrice) 
        payable
        external 
    {
        (uint256 sizeDelta, uint256 collateralDelta, , , , , , ) = gmxVault.getPosition(address(this), collateralToken, indexToken, false);

        uint256 executionFee = gmxPositionRouter.minExecutionFee();
        // bool withdrawETH = false; // Set to true if you want to receive ETH instead of the collateral token

        gmxPositionRouter.createDecreasePosition{ value: executionFee }(
            path,
            indexToken,
            collateralDelta,
            sizeDelta,
            isLong,
            _recipient,
            _acceptablePrice,
            _minOut,
            executionFee,
            false,
            address(this)
        );

        getGmxPosition();
    }

    function gmxPositionCallback(bytes32 positionKey, bool isExecuted, bool isIncrease) external {

        if (!isIncrease) {
            
            uint256 collateralAmount = IERC20(collateralToken).balanceOf(address(this));
            IERC20(collateralToken).safeTransfer(account, collateralAmount);
            console.log("collateralAmount: %s", collateralAmount);
        }
        console.logBytes32(positionKey);
        console.log("isExecuted: %s", isExecuted);
        console.log("isIncrease: %s", isIncrease);
    }

    function getGmxPosition() 
        public view
        returns (uint256 sizeDelta, uint256 collateral)
    {
        (sizeDelta, collateral, , , , , , ) = gmxVault.getPosition(address(this), collateralToken, indexToken, false);
        console.log("sizeDelta: %s", sizeDelta);
        console.log("collateral: %s", collateral);
        console.log("collateral amount: ", IERC20(collateralToken).balanceOf(address(this)));
    }
}