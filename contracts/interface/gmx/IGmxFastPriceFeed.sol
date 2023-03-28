// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGmxFastPriceFeed {

    function setPricesWithBitsAndExecute(
        uint256 _priceBits,
        uint256 _timestamp,
        uint256 _endIndexForIncreasePositions,
        uint256 _endIndexForDecreasePositions,
        uint256 _maxIncreasePositions,
        uint256 _maxDecreasePositions
    ) external;

    function setPricesWithBits(uint256 _priceBits, uint256 _timestamp) external;

    function gov() external view returns (address);

    function setUpdater(address _account, bool _isActive) external;

    event DisableFastPrice(address signer);
    event EnableFastPrice(address signer);
    event PriceData(address token, uint256 refPrice, uint256 fastPrice, uint256 cumulativeRefDelta, uint256 cumulativeFastDelta);
    event PriceUpdate(address token, uint256 price, address priceFeed);
    event GlobalShortDataUpdated(address indexed token, uint256 globalShortSize, uint256 globalShortAveragePrice);
    event MaxCumulativeDeltaDiffExceeded(address token, uint256 refPrice, uint256 fastPrice, uint256 cumulativeRefDelta, uint256 cumulativeFastDelta);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event ClosePosition(
        bytes32 key,
        uint256 size,
        uint256 collateral,
        uint256 averagePrice,
        uint256 entryFundingRate,
        uint256 reserveAmount,
        int256 realisedPnl
    );
    event ExecuteDecreasePosition(
        address indexed account,
        address[] path,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        address receiver,
        uint256 acceptablePrice,
        uint256 minOut,
        uint256 executionFee,
        uint256 blockGap,
        uint256 timeGap
    );
}
