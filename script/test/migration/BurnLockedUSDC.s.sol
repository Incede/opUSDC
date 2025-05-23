// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from 'forge-std/Script.sol';
import {IL1OpEURCBridgeAdapter} from 'interfaces/IL1OpEURCBridgeAdapter.sol';

/// Warning: Script created only for testing purposes.
contract BurnLockedEURC is Script {
  IL1OpEURCBridgeAdapter public immutable L1_ADAPTER = IL1OpEURCBridgeAdapter(vm.envAddress('L1_ADAPTER'));
  address public burnCaller = vm.rememberKey(vm.envUint('BURN_CALLER_PK'));

  function run() public {
    vm.startBroadcast(burnCaller);
    L1_ADAPTER.burnLockedEURC();
    vm.stopBroadcast();
  }
}
