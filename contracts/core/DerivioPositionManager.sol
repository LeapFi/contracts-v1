// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interface/IProtocolPositionManager.sol";
import "hardhat/console.sol";

contract DerivioPositionManager is ReentrancyGuard {

    address public admin;
    mapping(address => bool) public isManager;

    mapping(bytes32 => OpenInfo) public protocolPositions;
    mapping(address => bytes32[]) public accountKeys;

    // account address => nextId
    mapping(address => uint256) public nextId;
    
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

    event AddPosition(address account, bytes32 positionKey);
    event AddResult(bytes32 positionKey, address manager, bytes32 key, bytes infos);
    event RemovePosition(address account, bytes32 positionKey);
    event RemovePositionFail(address account, bytes32 positionKey);
    event SetManager(address account, bool isActive);
    
    modifier onlyAdmin() {
        require(msg.sender == admin, "DerivioPositionManager: forbidden");
        _;
    }

    modifier onlyManager() {
        require(isManager[msg.sender], "DerivioPositionManager: forbidden");
        _;
    }

    function setManager(address _account, bool _isActive) external onlyAdmin {
        isManager[_account] = _isActive;
        emit SetManager(_account, _isActive);
    }

    function validatePositionOwner(address _account, bytes32 _positionKey) 
        internal view 
    {
        OpenInfo memory position = positionOf(_positionKey);
        require(position.account == _account, "Account don't own the position");
    }

    constructor () 
    {
        admin = msg.sender;
    }

    function openProtocolsPosition(address _account, OpenArg[] memory _args, uint256 _keeperFee)
        external payable nonReentrant onlyManager
        returns (OpenInfo memory result_) 
    {
        bytes32 positionKey = getNextPositionKey(_account);
        accountKeys[_account].push(positionKey);
        OpenInfo storage pos = protocolPositions[positionKey];

        pos.account = _account;
        pos.timestamp = block.timestamp;
        pos.keeperFee = _keeperFee;

        for (uint i = 0; i < _args.length; i++) {

            _args[i].manager.receiveFund(msg.sender, _args[i].funds);
            (bytes32 key, bytes memory infos) = _args[i].manager
                .openPosition{ value: _args[i].value }(_account, _args[i].inputs);

            pos.openResults.push(OpenResult({
                manager: _args[i].manager,
                key: key,
                infos: infos
            }));

            emit AddResult(positionKey, address(_args[i].manager), key, infos);
        }

        emit AddPosition(_account, positionKey);

        return pos;
    }

    function closeProtocolsPosition(address _account, bytes32 _positionKey, CloseArg[] memory _args) 
        public payable nonReentrant onlyManager
        returns (CloseResult[] memory result_) 
    {
        validatePositionOwner(_account, _positionKey);

        result_ = new CloseResult[](_args.length);
        for (uint i = 0; i < _args.length; i++) {
            
            (bytes memory positionInfo, IProtocolPositionManager.Fund[] memory closedFunds) = 
                _args[i].manager.closePosition{ value: _args[i].value }(_account, _args[i].inputs);

            _args[i].manager.returnFund(msg.sender, closedFunds);

             result_[i] = CloseResult({
                manager: _args[i].manager,
                infos: positionInfo,
                funds: closedFunds
            });
        }

        removePositionInfo(_account, _positionKey);
    }

    function validatedIsLiquidated(bytes32 _positionKey) 
        external view
        returns (bool) 
    {
        OpenInfo memory position = positionOf(_positionKey);

        for (uint i = 0; i < position.openResults.length; i++) {

            bytes32 key = position.openResults[i].key; 
            if (position.openResults[i].manager.isLiquidated(key)) {
                return true;
            }
        }

        return false;
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

        emit RemovePosition(_account, _positionKey);
        emit RemovePositionFail(_account, _positionKey);
    }

    function feeOf(bytes32 _positionKey)
        public view
        returns (Fees[] memory result_)
    {
        OpenInfo memory position = positionOf(_positionKey);

        result_ = new Fees[](position.openResults.length);
        for (uint i = 0; i < position.openResults.length; i++) {
            result_[i].manager = position.openResults[i].manager;
            result_[i].fees = position.openResults[i].manager.feesOf(position.openResults[i].key);
        }
    }

    function claimFees(address _account, bytes32 _positionKey)
        public
    {
        validatePositionOwner(_account, _positionKey);(_positionKey);(_account, _positionKey);
        
        OpenInfo memory position = positionOf(_positionKey);

        for (uint i = 0; i < position.openResults.length; i++) {
            position.openResults[i].manager.claimFees(_account, position.openResults[i].key);
        }
    }

    function keeperFee(bytes32 _positionKey) 
        public view
        returns (uint256)
    {
        return protocolPositions[_positionKey].keeperFee;
    }

    function positionOf(bytes32 _positionKey) 
        public view
        returns (OpenInfo memory)
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
            result_[i].timestamp = protocolPositions[positionKeys[i]].timestamp;
            result_[i].aggregateInfos = getAggregateInfos(positionKeys[i]);
        }

        return result_;
    }

    function getAggregateInfos(bytes32 _positionKey) 
        internal view
        returns (AggregateInfo[] memory aggregateInfos_)
    {
        OpenInfo memory position = positionOf(_positionKey);

        aggregateInfos_ = new AggregateInfo[](position.openResults.length);

        for (uint i = 0; i < position.openResults.length; i++) {
            aggregateInfos_[i].openResult = position.openResults[i];
            aggregateInfos_[i].currentInfos = position.openResults[i].manager.infoOf(position.openResults[i].key);
            aggregateInfos_[i].fees = position.openResults[i].manager.feesOf(position.openResults[i].key);
        }
    }

    function getNextPositionKey(address _account)
        private
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_account, nextId[_account]++));
    }
}