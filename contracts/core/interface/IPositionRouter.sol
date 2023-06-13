// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "../DerivioPositionManager.sol";
import "../DerivioA.sol";
import "../DerivioFuture.sol";

interface IPositionRouter {

    function openDerivioAPositions(DerivioA.OpenArgs[] memory _argsList, address _token0, address _token1) 
        external payable returns (DerivioPositionManager.OpenResult[][] memory);

    function openDerivioFuturePositions(DerivioFuture.OpenArgs[] memory _argsList, address _collateralToken, address _indexToken)
        external payable returns (DerivioPositionManager.OpenResult[][] memory);
    
    function closeDerivioPosition(DerivioA.CloaseArgs[] memory _argsList, address _token0, address _token1) 
        external payable returns (IDerivioPositionManager.CloseResult[][] memory);

    function positionsOf(address _account) external view returns (DerivioPositionManager.OpenResult[] memory, uint[] memory);
}
