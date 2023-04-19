// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "../DerivioPositionManager.sol";
import "../DerivioA.sol";

interface IPositionRouter {

    function openDerivioA(DerivioA.PositionArgs memory _args, address _token0, address _token1) external payable;
    function closeDerivioA(bytes32[] memory _positionKeys, address _token0, address _token1) external payable;
    function positionsOf(address _account) external view returns (DerivioPositionManager.ProtocolPosition[] memory, uint[] memory);

    function getPairId(uint32 _derivioId, address _token0, address _token1) external pure returns (bytes32 pairId);
    function getDerivioAddress(uint32 _derivioId, address _token0, address _token1) external view returns (address);

    function getGmxPosition(address _token0, address _token1) external view returns (uint256 sizeDelta, uint256 collateral);
}
