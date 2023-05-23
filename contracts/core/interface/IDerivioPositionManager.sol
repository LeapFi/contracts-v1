// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "./IProtocolPositionManager.sol";

interface IDerivioPositionManager {

    struct Position {
        bytes32 positionKey;
        AggregateInfo[] aggregateInfos;
    }

    struct AggregateInfo {
        ProtocolOpenResult openResult;
        uint256 timestamp;
        bytes currentInfos;
        IProtocolPositionManager.Fund[] fees;
    }

    struct ProtocolOpenArg {
        IProtocolPositionManager manager;
        uint256 value;
        IProtocolPositionManager.Fund[] funds;
        bytes inputs;
    }

    struct ProtocolOpenResult {
        IProtocolPositionManager manager;
        uint256 timestamp;
        bytes32 key;
        bytes infos;
    }

    struct ProtocolCloseArg {
        IProtocolPositionManager manager;
        uint256 value;
        bytes inputs;
    }

    struct ProtocolCloseResult {
        IProtocolPositionManager manager;
        bytes infos;
        IProtocolPositionManager.Fund[] funds;
    }

    struct ProtocolFees {
        IProtocolPositionManager manager;
        IProtocolPositionManager.Fund[] fees;
    }

    function openProtocolsPosition(
        address _account,
        ProtocolOpenArg[] memory _args
    ) external payable returns (ProtocolOpenResult[] memory result_);

    function closeProtocolsPosition(
        address _account,
        bytes32 _positionKey,
        ProtocolCloseArg[] memory _args
    ) external payable returns (ProtocolCloseResult[] memory result_);

    function feeOf(bytes32 _positionKey) external view returns (ProtocolFees[] memory result_);

    function claimFees(address _account, bytes32 _positionKey) external;

    function positionOf(bytes32 _positionKey) external view returns (ProtocolOpenResult[] memory);

    function getAllPositionKeys(address _account) external view returns (bytes32[] memory);

    function getAllPositions(address _account) external view returns (Position[] memory);
}
