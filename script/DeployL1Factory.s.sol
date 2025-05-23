// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {L1OpEURCFactory} from 'contracts/L1OpEURCFactory.sol';
import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/Test.sol';
import {IL1OpEURCFactory} from 'interfaces/IL1OpEURCFactory.sol';

contract DeployL1Factory is Script {
  address public deployer = vm.rememberKey(vm.envUint('PRIVATE_KEY'));
  address public eurc = vm.envAddress('EURC_ETHEREUM_PROXY');

  function run() public {
    vm.startBroadcast(deployer);
    console.log('Deploying L1OpEURCFactory ...');
    IL1OpEURCFactory _l1Factory = new L1OpEURCFactory(eurc);
    console.log('L1OpEURCFactory deployed at:', address(_l1Factory));
    /// NOTE: Hardcode the newly deployed `_l1Factory` address on `L1_FACTORY` inside the `.env` or `.env.testnet` file
    vm.stopBroadcast();
  }
}
