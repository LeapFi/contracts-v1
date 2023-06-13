// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interface/token/IWETH.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "hardhat/console.sol";

contract OrderManager is ReentrancyGuard {

    address public admin;
    address public weth;
    
    mapping(uint256 => uint256) productKeeperFee;
    mapping(address => bool) isManager;

    modifier onlyAdmin() {
        require(msg.sender == admin, "OrderManager: forbidden");
        _;
    }

    modifier onlyManager() {
        require(isManager[msg.sender], "OrderManager: forbidden");
        _;
    }

    constructor (address _weth) 
    {
        admin = msg.sender;
        weth = _weth;
    }

    function setKeeperFee(uint256 _productId, uint256 _keeperFee) 
        external onlyAdmin
    {
        productKeeperFee[_productId] = _keeperFee;
    }

    function keeperFeeOf(uint256 _productId)
        external view returns(uint256)
    {
        return productKeeperFee[_productId];
    }

    function setManager(address _manager, bool _active)
        external onlyAdmin
    {
        isManager[_manager] = _active;
    }

    function receiveKeeperFee(uint256 _productId) 
        external payable
    {
        transferInETH(productKeeperFee[_productId]);
    }

    // Execution fee pay by the keeper, it will return to user if he close position by himself
    function transferInETH(uint256 amount)
        public payable
    {
        if (amount != 0) {
            IWETH(weth).deposit{value: amount}();
        }
    }

    function transferOutETH(uint256 _amount, address payable _receiver) 
        external onlyManager
    {
        if (_amount != 0) {

            IWETH(weth).withdraw(_amount);

            require(address(this).balance >= _amount, "Insufficient balance");
            (bool success, ) = _receiver.call{ value: _amount }("");
            require(success, "Unable to send value, recipient may have reverted");
        }
    }

    receive() external payable {
        require(msg.sender == weth, "OrderManager: invalid sender");
    }

}