// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/Test.sol';
import {IL1OpEURCFactory} from 'interfaces/IL1OpEURCFactory.sol';
import {IEURC} from 'interfaces/external/IEURC.sol';
import {EURCInitTxs} from 'src/contracts/utils/EURCInitTxs.sol';

contract DeployProtocol is Script {
  uint32 public constant MIN_GAS_LIMIT_DEPLOY = 9_000_000;
  IL1OpEURCFactory public immutable L1_FACTORY = IL1OpEURCFactory(vm.envAddress('L1_FACTORY'));
  address public immutable BRIDGED_EURC_IMPLEMENTATION = vm.envAddress('BRIDGED_EURC_IMPLEMENTATION');
  address public immutable L1_MESSENGER = vm.envAddress('L1_MESSENGER');
  string public chainName = vm.envString('CHAIN_NAME');
  address public owner = vm.rememberKey(vm.envUint('PRIVATE_KEY'));

  function run() public {
    vm.startBroadcast(owner);

    // NOTE: We have these hardcoded to default values, if used in production you will need to change them
    bytes[] memory _eurcInitTxs = new bytes[](3);
    string memory _name = string.concat('Bridged EURC', ' ', '(', chainName, ')');

    _eurcInitTxs[0] = abi.encodeCall(IEURC.initializeV2, (_name));
    _eurcInitTxs[1] = EURCInitTxs.INITIALIZEV2_1;
    _eurcInitTxs[2] = EURCInitTxs.INITIALIZEV2_2;

    // Sanity check to ensure the caller of this script changed this value to the proper naming
    assert(keccak256(_eurcInitTxs[0]) != keccak256(EURCInitTxs.INITIALIZEV2));

    IL1OpEURCFactory.L2Deployments memory _l2Deployments = IL1OpEURCFactory.L2Deployments({
      l2AdapterOwner: owner,
      eurcImplAddr: BRIDGED_EURC_IMPLEMENTATION,
      eurcInitTxs: _eurcInitTxs,
      minGasLimitDeploy: MIN_GAS_LIMIT_DEPLOY
    });

    // Deploy the L2 contracts
    (address _l1Adapter, address _l2Deploy, address _l2Adapter) =
      L1_FACTORY.deploy(L1_MESSENGER, owner, chainName, _l2Deployments);
    vm.stopBroadcast();

    /// NOTE: Hardcode the newly deployed `_l1Adapter` address on `L1_ADAPTER` inside the `.env` or `env.example` file
    console.log('L1 Adapter:', _l1Adapter);
    console.log('L2 Deploy:', _l2Deploy);
    console.log('L2 Adapter:', _l2Adapter);
  }
}
