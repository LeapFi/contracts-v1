// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../protocols-manager/GmxManager.sol";
import "./interface/IDerivioPositionManager.sol";
import "hardhat/console.sol";

contract DerivioFuture is ReentrancyGuard {

    using SafeERC20 for IERC20;
    IERC20 immutable collateralToken;
    IERC20 immutable indexToken;

    IDerivioPositionManager private immutable derivioPositionManager;
    GmxManager private immutable gmxManager;

    struct OpenArgs {
        address recipient;
        uint256 value;
        bool isLong;
        uint256 collateralAmount;
        uint256 sizeDelta;
        uint256 acceptPrice;
    }

    struct CloseArgs {
        uint256 value;
        bytes32 positionKey;
        uint256 minOut;
        uint256 acceptPrice;
    }

    constructor (
        IDerivioPositionManager _derivioPositionManager,
        GmxManager _gmxManager,
        address _collateralToken,
        address _indexToken
        ) 
    {
        derivioPositionManager = IDerivioPositionManager(_derivioPositionManager);
        gmxManager = GmxManager(_gmxManager);
        
        collateralToken = IERC20(_collateralToken);
        indexToken = IERC20(_indexToken);
    }

    function openFuture(OpenArgs memory _args)
        external payable nonReentrant 
        returns (IDerivioPositionManager.ProtocolOpenResult[] memory) 
    {
        collateralToken.safeTransferFrom(msg.sender, address(this), _args.collateralAmount);
        collateralToken.approve(address(gmxManager), _args.collateralAmount);

        IDerivioPositionManager.ProtocolOpenArg[] memory openArgs = new IDerivioPositionManager.ProtocolOpenArg[](1);
        openArgs[0] = createGmxProtocolOpenArg(_args.value, _args.isLong, _args.collateralAmount, _args.sizeDelta, _args.acceptPrice);

        // Open positions
        return derivioPositionManager.openProtocolsPosition{ value: _args.value }(_args.recipient, openArgs);
    }

    function createGmxProtocolOpenArg(uint256 _value, bool _isLong, uint256 _collateralAmount, uint256 _sizeDelta, uint256 _acceptPrice) 
        internal view 
        returns (IDerivioPositionManager.ProtocolOpenArg memory gmxArg) 
    {
        gmxArg = IDerivioPositionManager.ProtocolOpenArg({
            manager: gmxManager,
            value: _value,
            funds: new IProtocolPositionManager.Fund[](1),
            inputs: abi.encode(
                address(collateralToken),
                address(indexToken),
                _isLong,
                _collateralAmount,
                _sizeDelta,
                _acceptPrice
            )
        });

        gmxArg.funds[0].token = address(collateralToken);
        gmxArg.funds[0].amount = _collateralAmount;
    }

    function closeFuture(address _account, CloseArgs memory _args)
        external payable nonReentrant 
        returns (IDerivioPositionManager.ProtocolCloseResult[] memory)
    {
        IDerivioPositionManager.ProtocolOpenResult[] memory position = derivioPositionManager.positionOf(_args.positionKey);
        IDerivioPositionManager.ProtocolCloseArg[] memory protocolCloseArgs = new IDerivioPositionManager.ProtocolCloseArg[](position.length);

        require(position.length == 1, "Only allow one protocol position");

        for (uint i = 0; i < position.length; i++) { 

            require(position[i].manager == gmxManager, "Position manager error");

            protocolCloseArgs[i] = IDerivioPositionManager.ProtocolCloseArg({
                manager: gmxManager,
                inputs: abi.encode(position[i].key, _args.minOut, _args.acceptPrice),
                value: _args.value
            });
        }

        return derivioPositionManager.closeProtocolsPosition{ value: _args.value }(_account, _args.positionKey, protocolCloseArgs);
    }
}