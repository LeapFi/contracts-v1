// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IProtocolPosition {
    
    function openPosition(address _account, bytes32[] calldata _args) external payable returns (bytes32[] memory);
    function closePosition(address _account, bytes32[] calldata _args) external payable returns (bytes32[] memory);
}
