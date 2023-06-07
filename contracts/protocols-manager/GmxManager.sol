// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../interface/gmx/IGmxPositionRouter.sol";
import "../interface/gmx/IGmxRouter.sol";
import "../interface/gmx/IGmxVault.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./MimGmxPosition.sol";
import "../core/DerivioPositionManager.sol";
import "../core/interface/IProtocolPositionManager.sol";
import "hardhat/console.sol";

contract GmxManager is ReentrancyGuard, IProtocolPositionManager {

    using SafeERC20 for IERC20;

    IGmxPositionRouter private immutable gmxPositionRouter;
    IGmxRouter private immutable gmxRouter;
    IGmxVault private immutable gmxVault;
    uint256 private constant gmxDecimals = 30;

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

    function openPosition(address _account, bytes calldata _args)
        external payable override
        returns (bytes32 key_, bytes memory result_)
    {
        (
            address _collateralToken,
            address _indexToken,
            bool _isLong,
            uint256 _collateralAmount,
            uint256 _sizeDelta,
            uint256 _acceptPrice
        ) = abi.decode(_args, (address, address, bool, uint256, uint256, uint256));

        require(_sizeDelta >= _collateralAmount, "delta size too small");

        MimGmxPosition mimGmxPosition = new MimGmxPosition(
            _account,
            gmxPositionRouter,
            gmxRouter,
            gmxVault,
            _isLong,
            _collateralToken,
            _indexToken
        );

        _sizeDelta *= 10 ** (gmxDecimals - uint256(IERC20Metadata(_collateralToken).decimals()));

        IERC20(_collateralToken).safeTransfer(address(mimGmxPosition), _collateralAmount);
        mimGmxPosition.openGmxPosition{ value: msg.value }(
            _collateralAmount,
            _sizeDelta,
            _acceptPrice
        );
        
        key_ = bytes32(uint256(uint160(address(mimGmxPosition))));
        result_ = abi.encode(
            _collateralToken,
            _indexToken,
            _isLong,
            _collateralAmount,
            _sizeDelta
        ); 
    }

    function closePosition(address _account, bytes calldata _args)
        external payable override
        returns (bytes memory, Fund[] memory) 
    {
        // Parse the input arguments
        (
            address mimGmxPositionAddress,
            uint256 _minOut,
            uint256 _acceptPrice
        ) = abi.decode(_args, (address, uint256, uint256));

        // Ensure that the position actually exists
        require(mimGmxPositionAddress != address(0), "GMX position not found");

        // Call closeGmxShort on the MimGmxPosition contract
        MimGmxPosition(mimGmxPositionAddress).closeGmxPosition{value: msg.value}(_account, _minOut, _acceptPrice);

        // Currently, there are no return values for closePosition
        bytes memory result = abi.encode(new bytes32[](0));
        IProtocolPositionManager.Fund[] memory returnedFund = new IProtocolPositionManager.Fund[](0); 

        return (result, returnedFund);
    }

    function infoOf(bytes32 _key) external view override returns (bytes memory info_) {

        address minVaultAddr = address(uint160(uint256(_key)));
        (
            bool isOpenSuccess,
            bool isCloseSuccess,
            bool isLong,
            uint256 contractCollateralAmount,
            uint256 sizeDelta, 
            uint256 collateral, 
            uint256 averagePrice, 
            uint256 entryFundingRate, 
            uint256 reserveAmount, 
            uint256 realisedPnl, 
            bool realisedPnLPositive, 
            uint256 lastIncreasedTime
        ) = MimGmxPosition(minVaultAddr).getGmxPosition();

        return abi.encode(isOpenSuccess, isCloseSuccess, isLong, contractCollateralAmount, 
            sizeDelta, collateral, averagePrice, entryFundingRate, 
            reserveAmount, realisedPnl, realisedPnLPositive, lastIncreasedTime
        );
    }

    function receiveFund(address _account, Fund[] memory _fund) external 
    {
        for (uint i = 0; i < _fund.length; i++) {
            IERC20(_fund[i].token).safeTransferFrom(_account, address(this), _fund[i].amount);
        }
    }

    function returnFund(address _account, Fund[] memory _fund) external 
    {
        for (uint i = 0; i < _fund.length; i++) {
            IERC20(_fund[i].token).safeTransfer(_account, _fund[i].amount);
        }
    }

    function feesOf(bytes32 _key) external view returns (Fund[] memory) 
    {
        return new Fund[](0);
    }

    function claimFees(address _account, bytes32 _key) external 
    {

    }

    function isLiquidated(bytes32 _key) external view returns (bool)
    {
        address minVaultAddr = address(uint160(uint256(_key)));
        (
            bool isOpenSuccess,
            ,
            ,
            ,
            uint256 sizeDelta, 
            , 
            , 
            , 
            , 
            , 
            , 
            uint256 lastIncreasedTime
        ) = MimGmxPosition(minVaultAddr).getGmxPosition();

        if (isOpenSuccess && sizeDelta == 0 && lastIncreasedTime == 0) {
            return true;
        }
        else {
            return false;
        }
    }
    
}