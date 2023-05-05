// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "../DerivioPositionManager.sol";
import "../DerivioA.sol";
import "../DerivioFuture.sol";

interface IPositionRouter {

    function openDerivioA(DerivioA.PositionArgs memory _args, address _token0, address _token1) external payable;
    function openDerivioAPositions(DerivioA.PositionArgs[] memory _argsList, address _token0, address _token1) external payable returns (DerivioPositionManager.ProtocolOpenResult[][] memory);
    function closeDerivioA(DerivioA.DerivioACloseArgs[] memory _argsList, address _token0, address _token1) external payable;
    function positionsOf(address _account) external view returns (DerivioPositionManager.ProtocolOpenResult[] memory, uint[] memory);

    function openDerivioFuturePositions(DerivioFuture.OpenArgs[] memory _argsList, address _collateralToken, address _indexToken)
        external payable returns (DerivioPositionManager.ProtocolOpenResult[][] memory);
    function closeDerivioFuture(DerivioFuture.CloseArgs[] memory _argsList, address _collateralToken, address _indexToken) 
        external payable returns (DerivioPositionManager.ProtocolCloseResult[][] memory);

    function getPairId(uint32 _derivioId, address _token0, address _token1) external pure returns (bytes32 pairId);
    function getDerivioAddress(uint32 _derivioId, address _token0, address _token1) external view returns (address);
}
