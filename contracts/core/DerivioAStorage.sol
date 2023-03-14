// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "./DerivioA.sol";

contract DerivioAStorage {

    // id => derivioA by token
    mapping(bytes32 => DerivioA) public byToken;

    function addPair (
        bytes32 pairId,
        DerivioA derivioA
        )
        public
    {
        require(address(byToken[pairId]) != address(0), "DerivioAPair exists!");
        
        byToken[pairId] = derivioA;
    }

    function getAddress (
        bytes32 pairId
        )
        public
        view
        returns (address)
    {
        return address(byToken[pairId]);
    }
}
