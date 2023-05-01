// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interface/IProtocolPosition.sol";
import "hardhat/console.sol";

contract DerivioPositionManager is ReentrancyGuard {

    mapping(bytes32 => ProtocolPosition[]) public protocolPositions;
    mapping(address => bytes32[]) public accountKeys;

    // account address => nextId
    mapping(address => uint256) public nextId;

    struct Pos {
        bytes32 positionKey;
        ProtocolPosition[] protocolPosition;
    }

    struct ProtocolPosition {
        address protocolManager;
        bytes32 key;
        bytes positionInfo;
        // IProtocolPosition.Fund[] fees;
    }

    struct ProtocolOpenArg {
        address protocolManager;
        uint256 senderValue;
        IProtocolPosition.Fund[] fund;
        bytes inputArgs;
    }

    struct ProtocolCloseArg {
        address protocolManager;
        uint256 senderValue;
        bytes inputArgs;
    }

    struct ProtocolCloseInfo {
        address protocolManager;
        bytes positionInfo;
        IProtocolPosition.Fund[] fund;
    }

    struct ProtocolFees {
        address protocolManager;
        IProtocolPosition.Fund[] fees;
    }

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
        returns (ProtocolPosition[] memory result_) 
    {
        result_ = new ProtocolPosition[](_args.length);
        for (uint i = 0; i < _args.length; i++) {

            IProtocolPosition(_args[i].protocolManager).receiveFund(msg.sender, _args[i].fund);
            (bytes32 key, bytes memory openResult) = IProtocolPosition(_args[i].protocolManager)
                .openPosition{ value: _args[i].senderValue }(_account, _args[i].inputArgs);

            result_[i] = ProtocolPosition({
                protocolManager: _args[i].protocolManager,
                key: key,
                positionInfo: openResult
                // fees: new IProtocolPosition.Fund[](0)
            });
        }

        addPositionInfo(_account, result_);
    }

    function closeProtocolsPosition(address _account, bytes32 _positionKey, ProtocolCloseArg[] memory _args) 
        external payable nonReentrant
        returns (ProtocolCloseInfo[] memory result_) 
    {
        verifyPositionOwner(_account, _positionKey);

        result_ = new ProtocolCloseInfo[](_args.length);
        for (uint i = 0; i < _args.length; i++) {

            IProtocolPosition protocolManager = IProtocolPosition(_args[i].protocolManager);

            (bytes memory positionInfo, IProtocolPosition.Fund[] memory closedFund) = 
                protocolManager.closePosition{ value: _args[i].senderValue }(_account, _args[i].inputArgs);

            protocolManager.returnFund(msg.sender, closedFund);

             result_[i] = ProtocolCloseInfo({
                protocolManager: _args[i].protocolManager,
                positionInfo: positionInfo,
                fund: closedFund
            });
        }

        removePositionInfo(_account, _positionKey);
    }

    function addPositionInfo(address _account, ProtocolPosition[] memory _protocolPositions)
        private
    {
        bytes32 key = getNextPositionKey(_account);
        accountKeys[_account].push(key);

        ProtocolPosition[] storage pos = protocolPositions[key];
        for (uint i = 0; i < _protocolPositions.length; i++) {
            pos.push(_protocolPositions[i]);
        }
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

                // The element has been removed, no need to continue the loop
                return;
            }
        }
    }

    function feeOf(bytes32 _positionKey)
        public view
        returns (ProtocolFees[] memory result_)
    {
        ProtocolPosition[] memory positions = positionOf(_positionKey);

        result_ = new ProtocolFees[](positions.length);
        for (uint i = 0; i < positions.length; i++) {
            result_[i].protocolManager = positions[i].protocolManager;
            result_[i].fees = IProtocolPosition(positions[i].protocolManager).feesOf(positions[i].key);
        }
    }

    function claimFees(address _account, bytes32 _positionKey)
        public
    {
        verifyPositionOwner(_account, _positionKey);
        
        ProtocolPosition[] memory positions = positionOf(_positionKey);

        for (uint i = 0; i < positions.length; i++) {
            IProtocolPosition(positions[i].protocolManager).claimFees(_account, positions[i].key);
        }
    }

    function positionOf(bytes32 positionKey) 
        public view
        returns (ProtocolPosition[] memory)
    {
        return protocolPositions[positionKey];
    }

    function getAllPositionKeys(address _account)
        public view
        returns (bytes32[] memory)
    {
        return accountKeys[_account];
    }

    function getAllPositions(address _account)
        public view 
        returns (Pos[] memory)
    {
        bytes32[] memory positionKeys = getAllPositionKeys(_account);
        Pos[] memory result_ = new Pos[](positionKeys.length);

        for (uint i = 0; i < positionKeys.length; i++) {
            result_[i].positionKey = positionKeys[i];
            result_[i].protocolPosition = positionOf(positionKeys[i]);
        }

        return result_;
    }

    function getNextPositionKey(address _recipient)
        private
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_recipient, nextId[_recipient]++));
    }
}