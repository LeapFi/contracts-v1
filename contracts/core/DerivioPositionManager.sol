// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interface/IProtocolPositionManager.sol";
import "hardhat/console.sol";

contract DerivioPositionManager is ReentrancyGuard {

    mapping(bytes32 => ProtocolOpenResult[]) public protocolPositions;
    mapping(address => bytes32[]) public accountKeys;

    // account address => nextId
    mapping(address => uint256) public nextId;

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

    event AddPosition(address account, bytes32 positionKey);
    event RemovePosition(address account, bytes32 positionKey);
    event RemovePositionFail(address account, bytes32 positionKey);

    function verifyPositionOwner(address _account, bytes32 _positionKey) internal view {

        bytes32[] memory keys = accountKeys[_account];
        bool positionExists = false;
        for (uint i = 0; i < keys.length; i++) {
            if (keys[i] == _positionKey) {
                positionExists = true;
                break;
            }
        }
        require(positionExists, "Position does not exist for the given account");
    }

    constructor () 
    {
        
    }

    function openProtocolsPosition(address _account, ProtocolOpenArg[] memory _args) 
        external payable nonReentrant
        returns (ProtocolOpenResult[] memory result_) 
    {
        result_ = new ProtocolOpenResult[](_args.length);
        for (uint i = 0; i < _args.length; i++) {

            _args[i].manager.receiveFund(msg.sender, _args[i].funds);
            (bytes32 key, bytes memory infos) = _args[i].manager
                .openPosition{ value: _args[i].value }(_account, _args[i].inputs);

            result_[i] = ProtocolOpenResult({
                manager: _args[i].manager,
                timestamp: block.timestamp,
                key: key,
                infos: infos
            });
        }

        addPositionInfo(_account, result_);
    }

    function closeProtocolsPosition(address _account, bytes32 _positionKey, ProtocolCloseArg[] memory _args) 
        external payable nonReentrant
        returns (ProtocolCloseResult[] memory result_) 
    {
        verifyPositionOwner(_account, _positionKey);

        result_ = new ProtocolCloseResult[](_args.length);
        for (uint i = 0; i < _args.length; i++) {
            
            (bytes memory positionInfo, IProtocolPositionManager.Fund[] memory closedFunds) = 
                _args[i].manager.closePosition{ value: _args[i].value }(_account, _args[i].inputs);

            _args[i].manager.returnFund(msg.sender, closedFunds);

             result_[i] = ProtocolCloseResult({
                manager: _args[i].manager,
                infos: positionInfo,
                funds: closedFunds
            });
        }

        removePositionInfo(_account, _positionKey);
    }

    function addPositionInfo(address _account, ProtocolOpenResult[] memory _openResults)
        private
    {
        bytes32 positionKey = getNextPositionKey(_account);
        accountKeys[_account].push(positionKey);

        ProtocolOpenResult[] storage pos = protocolPositions[positionKey];
        for (uint i = 0; i < _openResults.length; i++) {
            pos.push(_openResults[i]);
        }

        emit AddPosition(_account, positionKey);
    }

    function removePositionInfo(address _account, bytes32 _positionKey) 
        internal 
    {
        for (uint256 i = 0; i < accountKeys[_account].length; i++) {
            if (accountKeys[_account][i] == _positionKey) {
                // Replace the element with the last element in the array and remove the last element
                accountKeys[_account][i] = accountKeys[_account][accountKeys[_account].length - 1];
                accountKeys[_account].pop();

                // Remove the composedPositions from the mapping
                delete protocolPositions[_positionKey];

                emit RemovePosition(_account, _positionKey);

                // The element has been removed, no need to continue the loop
                return;
            }
        }

        emit RemovePositionFail(_account, _positionKey);
    }

    function feeOf(bytes32 _positionKey)
        public view
        returns (ProtocolFees[] memory result_)
    {
        ProtocolOpenResult[] memory positions = positionOf(_positionKey);

        result_ = new ProtocolFees[](positions.length);
        for (uint i = 0; i < positions.length; i++) {
            result_[i].manager = positions[i].manager;
            result_[i].fees = positions[i].manager.feesOf(positions[i].key);
        }
    }

    function claimFees(address _account, bytes32 _positionKey)
        public
    {
        verifyPositionOwner(_account, _positionKey);
        
        ProtocolOpenResult[] memory positions = positionOf(_positionKey);

        for (uint i = 0; i < positions.length; i++) {
            positions[i].manager.claimFees(_account, positions[i].key);
        }
    }

    function positionOf(bytes32 _positionKey) 
        public view
        returns (ProtocolOpenResult[] memory)
    {
        return protocolPositions[_positionKey];
    }

    function getAllPositionKeys(address _account)
        public view
        returns (bytes32[] memory)
    {
        return accountKeys[_account];
    }

    function getAllPositions(address _account)
        public view 
        returns (Position[] memory)
    {
        bytes32[] memory positionKeys = getAllPositionKeys(_account);
        Position[] memory result_ = new Position[](positionKeys.length);

        for (uint i = 0; i < positionKeys.length; i++) {
            result_[i].positionKey = positionKeys[i];
            result_[i].aggregateInfos = getAggregateInfos(positionKeys[i]);
        }

        return result_;
    }

    function getAggregateInfos(bytes32 _positionKey) 
        internal view
        returns (AggregateInfo[] memory aggregateInfos_)
    {
        ProtocolOpenResult[] memory positions = positionOf(_positionKey);

        aggregateInfos_ = new AggregateInfo[](positions.length);

        for (uint i = 0; i < positions.length; i++) {
            aggregateInfos_[i].openResult = positions[i];
            aggregateInfos_[i].timestamp = positions[i].timestamp;
            aggregateInfos_[i].currentInfos = positions[i].manager.infoOf(positions[i].key);
            aggregateInfos_[i].fees = positions[i].manager.feesOf(positions[i].key);
        }
    }

    function getNextPositionKey(address _account)
        private
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_account, nextId[_account]++));
    }
}