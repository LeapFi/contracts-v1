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
    address[] path;
    bool isLong;
    uint256 private constant gmxDecimals = 30;

    bool isOpenSuccess;
    bool isCloseSuccess;

    IGmxPositionRouter private immutable gmxPositionRouter;
    IGmxRouter private immutable gmxRouter;
    IGmxVault private immutable gmxVault;

    constructor (
        address _account,
        IGmxPositionRouter _gmxPositionRouter,
        IGmxRouter _gmxRouter,
        IGmxVault _gmxVault,
        bool _isLong,
        address _collateralToken,
        address _indexToken
        ) 
    {
        account = _account;
        gmxPositionRouter = _gmxPositionRouter;
        gmxRouter = _gmxRouter;
        gmxVault = _gmxVault;

        isLong = _isLong;
        collateralToken = _collateralToken;
        indexToken = _indexToken;

        _gmxRouter.approvePlugin(address(_gmxPositionRouter));

        if (isLong) {
            path = new address[](2);
            path[0] = collateralToken;
            path[1] = indexToken;
            console.log('collateralToken:', collateralToken);
            console.log('indexToken:', indexToken);
        }
        else {
            path = new address[](1);
            path[0] = collateralToken;
        }
    }

    function openGmxPosition(uint256 _collateralAmount, uint256 _sizeDelta, uint256 _acceptPrice) 
        external payable
    {
        console.log("collateral balance before:", IERC20(collateralToken).balanceOf(address(this)));
        IERC20(collateralToken).approve(address(gmxRouter), _collateralAmount);

        bytes32 referralCode = 0;
        uint256 executionFee = msg.value;
        
        console.log('MimVaultAddr:', address(this));
        console.log('msg.value', msg.value);
        console.log('executionFee', executionFee);
        console.log('path length:', path.length);
        console.log('path', path[0]);
        console.log('indexToken', indexToken);
        console.log('_collateralAmount', _collateralAmount);
        console.log('_sizeDelta', _sizeDelta);
        console.log('isLong', isLong);
        console.log('_acceptPrice', _acceptPrice);
        console.logBytes32(referralCode);

        gmxPositionRouter.createIncreasePosition{ value: executionFee }(
            path, 
            indexToken, 
            _collateralAmount,
            0,
            _sizeDelta, 
            isLong, 
            _acceptPrice, 
            executionFee,
            referralCode,
            address(this)
        );
        
        console.log("collateral balance after:", IERC20(collateralToken).balanceOf(address(this)));
        getGmxPosition();
    }

    function closeGmxPosition(address _recipient, uint256 _minOut, uint256 _acceptablePrice) 
        external payable 
    {
        (uint256 sizeDelta, uint256 collateralDelta, , , , , , ) = gmxVault.getPosition(address(this), collateralToken, indexToken, isLong);
        uint256 executionFee = msg.value;
        
        console.log('_recipient:', _recipient);
        console.log('_minOut:', _minOut);
        console.log('_acceptablePrice:', _acceptablePrice);
        console.log('sizeDelta:', sizeDelta);
        console.log('path:', path[0]);
        console.log('indexToken:', indexToken);
        console.log('isLong:', isLong);
        console.log('msg.value:', msg.value);

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
    }

    function gmxPositionCallback(bytes32 _positionKey, bool _isExecuted, bool _isIncrease) external 
    {
        if (_isIncrease && _isExecuted) {
            isOpenSuccess = true;
        }
        else if (!_isIncrease && _isExecuted) {
            isCloseSuccess = true;
        }

        if (!_isIncrease) {
            
            uint256 collateralAmount = IERC20(collateralToken).balanceOf(address(this));
            IERC20(collateralToken).safeTransfer(account, collateralAmount);
            console.log("collateralAmount: %s", collateralAmount);
        }

        if (!_isExecuted) {
            
            // console.log("returning collateral amount..........");
            // uint256 collateralAmount = IERC20(collateralToken).balanceOf(address(this));
            // IERC20(collateralToken).safeTransfer(account, collateralAmount);
        }

        console.logBytes32(_positionKey);
        console.log("isExecuted: %s", _isExecuted);
        console.log("isIncrease: %s", _isIncrease);
    }

    function getGmxPosition() 
        public view
        returns (
            bool isLong_, uint256 sizeDelta_, uint256 collateral_, uint256 averagePrice_, uint256 entryFundingRate_, 
            uint256 reserveAmount_, uint256 realisedPnl_, bool realisedPnLPositive_, uint256 lastIncreasedTime_
        )
    {
        isLong_ = isLong;
        (sizeDelta_, collateral_, averagePrice_, entryFundingRate_, 
        reserveAmount_, realisedPnl_, realisedPnLPositive_, lastIncreasedTime_) = gmxVault.getPosition(address(this), collateralToken, indexToken, isLong);

        console.log('MimVaultAddr:', address(this));
        console.log("isLong: %s", isLong);
        console.log("sizeDelta: %s", sizeDelta_);
        console.log("collateral: %s", collateral_);
        console.log("entryFundingRate_: %s", entryFundingRate_);
        console.log("reserveAmount_: %s", reserveAmount_);
        console.log("lastIncreasedTime_: %s", lastIncreasedTime_);
        console.log("collateral amount: ", IERC20(collateralToken).balanceOf(address(this)));
        console.log("index amount: ", IERC20(indexToken).balanceOf(address(this)));

        // require(IERC20(collateralToken).balanceOf(address(this)) == 0, "collateral amount should be 0");
    }
}