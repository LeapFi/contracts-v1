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
        bool transferFromRecipient;
        bool isLong;
        uint256 collateralAmount;
        uint256 sizeDelta;
        uint256 acceptPrice;
    }

    struct CloseArgs {
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

    function openFuture(OpenArgs memory _args, uint256 _keeperFee)
        external payable nonReentrant 
        returns (IDerivioPositionManager.OpenInfo memory) 
    {
        collateralToken.safeTransferFrom(msg.sender, address(this), _args.collateralAmount);
        collateralToken.approve(address(gmxManager), _args.collateralAmount);

        uint256 gmxExecutionFee = gmxManager.minExecutionFee();

        IDerivioPositionManager.OpenArg[] memory openArgs = new IDerivioPositionManager.OpenArg[](1);
        openArgs[0] = createGmxProtocolOpenArg(gmxExecutionFee, _args.isLong, _args.collateralAmount, _args.sizeDelta, _args.acceptPrice);

        // Open positions
        return derivioPositionManager.openProtocolsPosition{ value: gmxExecutionFee }(_args.recipient, openArgs, _keeperFee);
    }

    function createGmxProtocolOpenArg(uint256 _value, bool _isLong, uint256 _collateralAmount, uint256 _sizeDelta, uint256 _acceptPrice) 
        internal view 
        returns (IDerivioPositionManager.OpenArg memory gmxArg) 
    {
        gmxArg = IDerivioPositionManager.OpenArg({
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
        returns (IDerivioPositionManager.CloseResult[] memory)
    {
        IDerivioPositionManager.OpenInfo memory position = derivioPositionManager.positionOf(_args.positionKey);
        IDerivioPositionManager.CloseArg[] memory protocolCloseArgs = new IDerivioPositionManager.CloseArg[](position.openResults.length);

        require(position.openResults.length == 1, "Only allow one protocol position");

        uint256 gmxExecutionFee = gmxManager.minExecutionFee();
        uint256 sumValue = 0;

        for (uint i = 0; i < position.openResults.length; i++) { 

            require(position.openResults[i].manager == gmxManager, "Position manager error");

            protocolCloseArgs[i] = IDerivioPositionManager.CloseArg({
                manager: gmxManager,
                inputs: abi.encode(position.openResults[i].key, _args.minOut, _args.acceptPrice),
                value: gmxExecutionFee
            });

            sumValue += gmxExecutionFee;
        }

        return derivioPositionManager.closeProtocolsPosition{ value: sumValue }(_account, _args.positionKey, protocolCloseArgs);
    }
}