// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "./IProtocolPositionManager.sol";

interface IDerivioPositionManager {

    struct Position {
        bytes32 positionKey;
        uint256 timestamp;
        AggregateInfo[] aggregateInfos;
    }

    struct AggregateInfo {
        OpenResult openResult;
        bytes currentInfos;
        IProtocolPositionManager.Fund[] fees;
    }

    struct OpenArg {
        IProtocolPositionManager manager;
        uint256 value;
        IProtocolPositionManager.Fund[] funds;
        bytes inputs;
    }

    struct OpenInfo {
        address account;
        uint256 timestamp;
        uint256 keeperFee;
        OpenResult[] openResults;
    }

    struct OpenResult {
        IProtocolPositionManager manager;
        bytes32 key;
        bytes infos;
    }

    struct CloseArg {
        IProtocolPositionManager manager;
        uint256 value;
        bytes inputs;
    }

    struct CloseResult {
        IProtocolPositionManager manager;
        bytes infos;
        IProtocolPositionManager.Fund[] funds;
    }

    struct Fees {
        IProtocolPositionManager manager;
        IProtocolPositionManager.Fund[] fees;
    }

    function openProtocolsPosition(
        address _account,
        OpenArg[] memory _args,
        uint256 _keeperFee
    ) external payable returns (OpenInfo memory result_);

    function closeProtocolsPosition(
        address _account,
        bytes32 _positionKey,
        CloseArg[] memory _args
    ) external payable returns (CloseResult[] memory result_);

    function validatedIsLiquidated(bytes32 _positionKey) external view returns (bool);

    function feeOf(bytes32 _positionKey) external view returns (Fees[] memory result_);

    function claimFees(address _account, bytes32 _positionKey) external;

    function keeperFee(bytes32 _positionKey) external view returns (uint256);

    function positionOf(bytes32 _positionKey) external view returns (OpenInfo memory);

    function getAllPositionKeys(address _account) external view returns (bytes32[] memory);

    function getAllPositions(address _account) external view returns (Position[] memory);

    function setManager(address _account, bool _isActive) external;
}
