// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IDerivioPositionManager.sol";
import "./IProtocolPositionManager.sol";

interface IDerivioA {

    struct OpenArgs {
        address recipient;
        int24 tickLower;
        int24 tickUpper;
        uint24 feeTier;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint128 shortLeverage;
        uint160 swapSqrtPriceLimitX96;
        uint256 shortPriceLimit;
    }

    struct CloseArgs {
        bytes32 positionKey;
        bool swapToCollateral;
    }

    struct ProtocolCloseResult {
        address manager;
        bytes32 key;
        IProtocolPositionManager.Fund[] funds;
    }

    function openAS(OpenArgs memory _args) external returns (IDerivioPositionManager.OpenInfo memory);
    function openAL(OpenArgs memory _args) external payable returns (IDerivioPositionManager.OpenInfo memory);

    function positionOf(bytes32 _positionKey) external view returns (IDerivioPositionManager.OpenResult[] memory);
    function closePosition(address payable _account, IDerivioPositionManager.CloseArg[] calldata _args) external payable returns (IDerivioPositionManager.CloseResult[] memory);
}
