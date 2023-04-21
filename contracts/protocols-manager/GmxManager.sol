// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import "../interface/gmx/IGmxPositionRouter.sol";
import "../interface/gmx/IGmxRouter.sol";
import "../interface/gmx/IGmxVault.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./MimGmxPosition.sol";
import "../core/DerivioPositionManager.sol";
import "../core/interface/IProtocolPosition.sol";
import "hardhat/console.sol";

contract GmxManager is ReentrancyGuard, IProtocolPosition {

    using SafeERC20 for IERC20;

    IGmxPositionRouter private immutable gmxPositionRouter;
    IGmxRouter private immutable gmxRouter;
    IGmxVault private immutable gmxVault;
    uint256 private constant gmxDecimals = 30;

    MimGmxPosition mimGmxPositionCont;

    constructor (
        IGmxPositionRouter _gmxPositionRouter,
        IGmxRouter _gmxRouter,
        IGmxVault _gmxVault
        ) 
    {
        gmxPositionRouter = _gmxPositionRouter;
        gmxRouter = _gmxRouter;
        gmxVault = _gmxVault;
    }

    function openPosition(address _account, bytes32[] calldata _args)
        external payable override
        returns (bytes32[] memory)
    {
        // Parse the input arguments
        address _collateralToken = address(uint160(uint256(_args[0])));
        address _indexToken = address(uint160(uint256(_args[1])));
        uint256 _collateralAmount = uint256(_args[2]);
        uint256 _shortDelta = uint256(_args[3]);
        uint256 _acceptPrice = uint256(_args[4]);

        require(_shortDelta >= _collateralAmount, "delta size too small");

        MimGmxPosition mimGmxPosition = new MimGmxPosition(
            _account,
            gmxPositionRouter,
            gmxRouter,
            gmxVault,
            _collateralToken,
            _indexToken
        );

        mimGmxPositionCont = mimGmxPosition;

        _shortDelta *= 10 ** (gmxDecimals - uint256(IERC20Metadata(_collateralToken).decimals()));

        IERC20(_collateralToken).safeTransfer(address(mimGmxPosition), _collateralAmount);
        mimGmxPosition.openGmxShort{ value: msg.value }(
            _collateralAmount,
            _shortDelta,
            _acceptPrice
        );
        mimGmxPosition.getGmxPosition();

        bytes32[] memory result = new bytes32[](1);
        result[0] = bytes32(uint256(uint160(address(mimGmxPosition))));

        return result;
    }

    function closePosition(address _account, bytes32[] calldata _args)
        external payable override
        returns (bytes32[] memory, Fund[] memory) 
    {
        // Parse the input arguments
        address mimGmxPositionAddress = address(uint160(uint256(_args[0])));
        uint256 _minOut = uint256(_args[1]);
        uint256 _acceptablePrice = uint256(_args[2]);

        // Ensure that the position actually exists
        require(mimGmxPositionAddress != address(0), "GMX position not found");

        // Call closeGmxShort on the MimGmxPosition contract
        MimGmxPosition(mimGmxPositionAddress).closeGmxShort{value: msg.value}(_account, _minOut, _acceptablePrice);

        // Currently, there are no return values for closePosition
        bytes32[] memory result = new bytes32[](0);

        IProtocolPosition.Fund[] memory returnedFund = new IProtocolPosition.Fund[](0); 

        return (result, returnedFund);
    }

    function getGmxPosition() 
        public view
        returns (uint256 sizeDelta, uint256 collateral)
    {
        return mimGmxPositionCont.getGmxPosition();
    }

    function receiveFund(address _fundingAcc, Fund[] memory _fund) external {
        
        for (uint i = 0; i < _fund.length; i++) {
            IERC20(_fund[i].token).safeTransferFrom(_fundingAcc, address(this), _fund[i].amount);
        }
    }

    function returnFund(address _fundingAcc, Fund[] memory _fund) external {
        
        for (uint i = 0; i < _fund.length; i++) {
            IERC20(_fund[i].token).safeTransfer(_fundingAcc, _fund[i].amount);
        }
    }
}