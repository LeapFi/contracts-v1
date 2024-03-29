// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "./DerivioA.sol";
import "hardhat/console.sol";

contract DerivioAStorage {

    // id => derivioA by token
    mapping(bytes32 => DerivioA) public byToken;
    bytes32[] pairIds;

    function addPair (
        bytes32 pairId,
        DerivioA derivioA
        )
        public
    {
        require(address(byToken[pairId]) == address(0), "DerivioAPair already exists!");
        
        byToken[pairId] = derivioA;
        pairIds.push(pairId);
    }

    function getAddress (
        bytes32 pairId
        )
        public
        view
        returns (address)
    {
        require(address(byToken[pairId]) != address(0), "pairId not exists!");

        return address(byToken[pairId]);
    }

    function getAllPairIds()
        public
        view
        returns (bytes32[] memory)
    {
        return pairIds;
    }
}
