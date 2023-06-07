// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IProtocolPositionManager {
    
    struct Fund {
        address token;
        uint256 amount;
    }

    function openPosition(address _account, bytes calldata _args) external payable returns (bytes32 key_, bytes memory result_);
    function closePosition(address _account, bytes calldata _args) external payable returns (bytes memory, Fund[] memory);
    function infoOf(bytes32 _key) external view returns (bytes memory info_);

    function receiveFund(address _account, Fund[] memory _fund) external;
    function returnFund(address _account, Fund[] memory _fund) external;
    
    function feesOf(bytes32 _key) external view returns (Fund[] memory); 
    function claimFees(address _account, bytes32 _key) external;

    function isLiquidated(bytes32 _key) external view returns (bool);
}
