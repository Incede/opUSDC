// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IEURC} from 'interfaces/external/IEURC.sol';

/**
 * @title FallbackProxyAdmin
 * @notice Middleware contract for the L2 Adapter to interact with the EURC proxy.
 * @dev The admin can't call the fallback function of the EURC proxy, meaning it can't interact with the functions
 * such as mint and burn between others. Because of this, the FallbackProxyAdmin contract is used as a middleware,
 * being controlled by the L2OpEURCBridgeAdapter contract and allowing to call the admin functions through it while
 * also being able to call the fallback function of the EURC proxy.
 */
contract FallbackProxyAdmin is Ownable {
  /// @notice EURC address
  address public immutable EURC;

  /**
   * @notice Construct the FallbackProxyAdmin contract
   * @param _eurc EURC address
   */
  constructor(address _eurc) Ownable(msg.sender) {
    EURC = _eurc;
  }

  /**
   * @notice Changes the admin of the EURC proxy
   * @param _newAdmin Address to transfer proxy administration to
   * @dev Owner should always be the L2 Adapter
   * @dev EURC admin cant interact proxy with implementation so we use this contract as the middleman
   */
  function changeAdmin(address _newAdmin) external onlyOwner {
    IEURC(EURC).changeAdmin(_newAdmin);
  }

  /**
   * @notice Function to upgrade the eurc proxy to a new implementation
   * @param _newImplementation Address of the new implementation
   */
  function upgradeTo(address _newImplementation) external onlyOwner {
    IEURC(EURC).upgradeTo(_newImplementation);
  }

  /**
   * @notice Upgrades the EURC proxy to a new implementation and calls a function on the new implementation
   * @param _newImplementation Address of the new implementation
   * @param _data Data to call on the new implementation
   */
  function upgradeToAndCall(address _newImplementation, bytes calldata _data) external onlyOwner {
    IEURC(EURC).upgradeToAndCall(_newImplementation, _data);
  }
}
