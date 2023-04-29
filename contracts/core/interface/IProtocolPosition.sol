// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IProtocolPosition {
    
    struct Fund {
        address token;
        uint256 amount;
    }

    function openPosition(address _account, bytes32[] calldata _args) external payable returns (bytes32 key_, bytes32[] memory result_);
    function closePosition(address _account, bytes32[] calldata _args) external payable returns (bytes32[] memory, Fund[] memory);

    function receiveFund(address _account, Fund[] memory _fund) external;
    function returnFund(address _account, Fund[] memory _fund) external;
    
    function feesOf(bytes32 _positionKey) external view returns (Fund[] memory); 
    function claimFees(address _account, bytes32 _positionKey) external;
}
