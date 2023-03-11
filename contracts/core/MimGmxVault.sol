// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interface/gmx/IGmxPositionRouter.sol";
import "../interface/gmx/IGmxRouter.sol";
import "../interface/gmx/IGmxVault.sol";
import "hardhat/console.sol";

contract MimGmxVault is ReentrancyGuard {

    using SafeERC20 for IERC20;
    
    address collateralToken;
    address indexToken;
    address[] path = new address[](1);
    bool isLong = false;

    IGmxPositionRouter private immutable gmxPositionRouter;
    IGmxRouter private immutable gmxRouter;
    IGmxVault private immutable gmxVault;

    constructor (
        IGmxPositionRouter _gmxPositionRouter,
        IGmxRouter _gmxRouter,
        IGmxVault _gmxVault,
        address _collateralToken,
        address _indexToken
        ) 
    {
        gmxPositionRouter = _gmxPositionRouter;
        gmxRouter = _gmxRouter;
        gmxVault = _gmxVault;
        collateralToken = _collateralToken;
        indexToken = _indexToken;

        _gmxRouter.approvePlugin(address(_gmxPositionRouter));
        path[0] = collateralToken;
    }

    function openGMXShort(
        uint256 _collateralAmount,
        uint256 _sizeDelta,
        uint256 _acceptPrice
    ) 
        payable
        external
    { 
        // IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), _collateralAmount);
        IERC20(collateralToken).approve(address(gmxRouter), _collateralAmount);

        bytes32 referralCode = 0;
        
        gmxPositionRouter.createIncreasePosition{value: msg.value}(
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

        getGMXPosition();
    }

    function getGMXPosition() 
        public
    {
        (uint256 sizeDelta,,,,,,,) = gmxVault.getPosition(address(this), indexToken, collateralToken, false);
        console.log("sizeDelta: %s", sizeDelta);
    }
}