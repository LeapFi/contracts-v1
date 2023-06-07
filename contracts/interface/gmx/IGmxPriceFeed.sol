// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGmxPriceFeed {
    function description() external view returns (string memory);
    function aggregator() external view returns (address);
    function latestAnswer() external view returns (int256);
    function latestRound() external view returns (uint80);
    function getRoundData(uint80 roundId) external view returns (uint80, int256, uint256, uint256, uint80);
    function setLatestAnswer(int256 _answer) external;
    function transmit(bytes calldata _report, bytes32[] calldata _rs, bytes32[] calldata _ss, bytes32 _rawVs) external;
}
