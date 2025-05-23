// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IEURC} from 'interfaces/external/IEURC.sol';

/**
 * @notice Library containing the initialization transactions constants (without the first one) for the EURC
 *  implementation contract defined by Circle.
 */
library EURCInitTxs {
  /**
   * @dev The `initializeV2()` transaction data for the EURC implementation contract.
   */
  bytes public constant INITIALIZEV2 = abi.encodeCall(IEURC.initializeV2, ('Bridged EURC'));

  /**
   * @dev The `initializeV2_1()` transaction data for the EURC implementation contract.
   */
  bytes public constant INITIALIZEV2_1 = abi.encodeCall(IEURC.initializeV2_1, (address(0)));

  /**
   * @dev The `initializeV2_2()` transaction data for the EURC implementation contract.
   */
  bytes public constant INITIALIZEV2_2 = abi.encodeCall(IEURC.initializeV2_2, (new address[](0), 'EURC.e'));
}
