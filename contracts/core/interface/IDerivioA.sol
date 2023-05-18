// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IDerivioPositionManager.sol";
import "./IProtocolPositionManager.sol";

interface IDerivioA {

    struct OpenArgs {
        address recipient;
        uint256 value;
        int24 tickLower;
        int24 tickUpper;
        uint24 feeTier;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint24 shortLeverage;
        uint160 swapSqrtPriceLimitX96;
        uint256 shortPriceLimit;
    }

    struct CloseArgs {
        uint256 value;
        bytes32 positionKey;
        bool swapToCollateral;
    }

    struct ProtocolCloseResult {
        address manager;
        bytes32 key;
        IProtocolPositionManager.Fund[] funds;
    }

    struct ProtocolOpenResult {
        address manager;
        bytes32 key;
    }

    struct ProtocolCloseArg {
        address manager;
        bytes inputs;
        uint256 value;
    }

    function openAS(OpenArgs memory _args) external returns (IDerivioPositionManager.ProtocolOpenResult[] memory);
    function openAL(OpenArgs memory _args) external payable returns (IDerivioPositionManager.ProtocolOpenResult[] memory);

    function positionOf(bytes32 positionKey) external view returns (ProtocolOpenResult[] memory);
    function closeProtocolsPosition(address account, bytes32 positionKey, ProtocolCloseArg[] calldata args) external payable returns (ProtocolCloseResult[] memory);
}
