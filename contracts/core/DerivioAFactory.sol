// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "./DerivioA.sol";
import "./DerivioFuture.sol";
import "hardhat/console.sol";

contract DerivioAFactory {

    // id => derivioA by token
    mapping(bytes32 => DerivioA) public byToken;
    mapping(bytes32 => DerivioFuture) public byTokenFuture;

    function getPairId(uint32 _derivioId, address _token0, address _token1) 
        public pure 
        returns (bytes32) 
    {
        return keccak256(abi.encodePacked(_derivioId, _token0, _token1));
    }

    function getFuturePairId(uint32 _derivioId, address _collateralToken, address _indexToken) 
        public pure 
        returns (bytes32) 
    {
        return keccak256(abi.encodePacked(_derivioId, _collateralToken, _indexToken));
    }
    
    // Need to make sure only admin can addPair
    function addPair(bytes32 _pairId, DerivioA _derivioA)
        public
    {
        require(address(byToken[_pairId]) == address(0), "DerivioAPair already exists!");
        byToken[_pairId] = _derivioA;
    }

    // Need to make sure only admin can addPair
    function addFuturePair(bytes32 _pairId, DerivioFuture _derivioFuture)
        public
    {
        require(address(byTokenFuture[_pairId]) == address(0), "DerivioAPair already exists!");
        byTokenFuture[_pairId] = _derivioFuture;
    }

    function getAddress(bytes32 _pairId)
        public view
        returns (address contractAddr_)
    {  
        contractAddr_ = address(byToken[_pairId]);
        require(contractAddr_ != address(0), "pairId not exists!");
    }

    function getFutureAddress(bytes32 _pairId)
        public view
        returns (address contractAddr_)
    {  
        contractAddr_ = address(byTokenFuture[_pairId]);
        require(contractAddr_ != address(0), "pairId not exists!");
    }
}
