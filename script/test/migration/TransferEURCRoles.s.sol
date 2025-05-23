// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from 'forge-std/Script.sol';
import {IL2OpEURCBridgeAdapter} from 'interfaces/IL2OpEURCBridgeAdapter.sol';

/// Warning: Script created only for testing purposes.
contract TransferEURCRoles is Script {
  IL2OpEURCBridgeAdapter public immutable L2_ADAPTER = IL2OpEURCBridgeAdapter(vm.envAddress('L2_ADAPTER'));

  address public roleCaller = vm.rememberKey(vm.envUint('ROLE_CALLER_PK'));
  address public newOwner = vm.envAddress('NEW_EURC_OWNER');

  function run() public {
    vm.startBroadcast(roleCaller);
    L2_ADAPTER.transferEURCRoles(newOwner);
    vm.stopBroadcast();
  }
}
