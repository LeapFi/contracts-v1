// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGmxPositionRouter {

    function createIncreasePosition(address[] memory _path, address _indexToken, uint256 _amountIn, uint256 _minOut, uint256 _sizeDelta, bool _isLong, uint256 _acceptablePrice, uint256 _executionFee, bytes32 _referralCode, address _callbackTarget) external payable;
    function createDecreasePosition(address[] memory _path, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver, uint256 _acceptablePrice, uint256 _minOut, uint256 _executionFee, bool _withdrawETH, address _callbackTarget) external payable;

    function minExecutionFee() external view returns (uint256);
    function getRequestQueueLengths() external view returns (uint256, uint256, uint256, uint256);
    function executeIncreasePositions(uint256 _endIndex, address payable _executionFeeReceiver) external;
}