// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGmxPositionManager {

    function setLiquidator(address _account, bool _isActive) external;
    function liquidatePosition(address _account, address _collateralToken, address _indexToken, bool _isLong, address _feeReceiver) external;
}