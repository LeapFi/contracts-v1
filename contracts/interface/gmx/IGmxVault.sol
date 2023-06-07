// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGmxVault {
    function getPosition(address _account, address _collateralToken, address _indexToken, bool _isLong) external view returns (uint256 size, uint256 collateral, uint256 averagePrice, uint256 entryFundingRate, uint256 reserveAmount, uint256 realisedPnl, bool realisedPnLPositive, uint256 lastIncreasedTime);
    
    function getMaxPrice(address _token) external view returns (uint256);
    function getMinPrice(address _token) external view returns (uint256);

    function validateLiquidation(address _account, address _collateralToken, address _indexToken, bool _isLong, bool _raise) external view returns (uint256, uint256);
}