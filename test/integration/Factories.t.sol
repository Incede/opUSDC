// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IntegrationBase} from './IntegrationBase.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

import {IL1OpEURCFactory} from 'interfaces/IL1OpEURCFactory.sol';
import {IL2OpEURCBridgeAdapter} from 'interfaces/IL2OpEURCBridgeAdapter.sol';
import {IL2OpEURCDeploy} from 'interfaces/IL2OpEURCDeploy.sol';
import {IOpEURCBridgeAdapter} from 'interfaces/IOpEURCBridgeAdapter.sol';
import {IEURC} from 'interfaces/external/IEURC.sol';
import {EURC_IMPLEMENTATION_CREATION_CODE} from 'test/utils/EURCImplementationCreationCode.sol';

contract Integration_Factories is IntegrationBase {
  /**
   * @notice Check all the L1 and L2 contracts are properly deployed and initialized
   */
  function test_deployAllContracts() public {
    vm.selectFork(mainnet);
    vm.roll(block.number + 1);

    IL1OpEURCFactory.L2Deployments memory _l2Deployments = l2Deployments;

    _l2Deployments.eurcInitTxs[0] = abi.encodeWithSignature('initializeV2(string)', 'Bridged EURC (Optimism)');

    // Deploy the contracts
    uint256 _deploymentsSaltCounter = l1Factory.deploymentsSaltCounter();
    vm.prank(_user);
    (address _l1Adapter, address _l2Factory, address _l2Adapter) =
      l1Factory.deploy(address(OPTIMISM_L1_MESSENGER), _owner, 'Optimism', _l2Deployments);

    // Check the adapter was properly deployed on L1
    assertEq(l1Factory.deploymentsSaltCounter(), _deploymentsSaltCounter + 2);
    assertEq(IOpEURCBridgeAdapter(_l1Adapter).EURC(), address(MAINNET_EURC), '1');
    assertEq(IOpEURCBridgeAdapter(_l1Adapter).MESSENGER(), address(OPTIMISM_L1_MESSENGER), '2');
    assertEq(IOpEURCBridgeAdapter(_l1Adapter).LINKED_ADAPTER(), _l2Adapter, '3');
    assertEq(Ownable(_l1Adapter).owner(), _owner);

    bytes32 _salt = bytes32(l1Factory.deploymentsSaltCounter());

    // Get the L1 values needed to assert the proper deployments on L2
    string memory _eurcSymbol = l1Factory.EURC_SYMBOL();
    uint8 _eurcDecimals = MAINNET_EURC.decimals();
    string memory _eurcCurrency = MAINNET_EURC.currency();

    vm.selectFork(optimism);
    IL2OpEURCDeploy.EURCInitializeData memory _eurcInitializeData = eurcInitializeData;
    _eurcInitializeData.tokenName = 'Bridged EURC (Optimism)';
    // Relay the L2 deployments message through the factory on L2
    _relayL2Deployments(OP_ALIASED_L1_MESSENGER, _salt, _l1Adapter, _eurcInitializeData, _l2Deployments);

    // Check the adapter was properly deployed on L2
    IEURC _l2Eurc = IEURC(IOpEURCBridgeAdapter(_l2Adapter).EURC());
    assertEq(IOpEURCBridgeAdapter(_l2Adapter).MESSENGER(), address(L2_MESSENGER), '4');
    assertEq(IOpEURCBridgeAdapter(_l2Adapter).LINKED_ADAPTER(), _l1Adapter, '5');
    assertEq(Ownable(_l2Adapter).owner(), _owner, '6');

    // Check the L2 factory was deployed
    assertGt(_l2Factory.code.length, 0, '7');

    // Check the EURC was properly deployed on L2
    assertEq(_l2Eurc.name(), 'Bridged EURC (Optimism)', '8');
    assertEq(_l2Eurc.symbol(), _eurcSymbol, '9');
    assertEq(_l2Eurc.decimals(), _eurcDecimals, '10');
    assertEq(_l2Eurc.currency(), _eurcCurrency, '11');
    assertGt(_l2Eurc.implementation().code.length, 0, '12');

    // Check the EURC permissions and allowances were properly set
    assertEq(_l2Eurc.admin(), address(IL2OpEURCBridgeAdapter(_l2Adapter).FALLBACK_PROXY_ADMIN()));
    assertEq(_l2Eurc.masterMinter(), _l2Adapter);
    assertEq(_l2Eurc.pauser(), _l2Adapter);
    assertEq(_l2Eurc.blacklister(), _l2Adapter);
    assertEq(_l2Eurc.isMinter(_l2Adapter), true);
    assertEq(_l2Eurc.minterAllowance(_l2Adapter), type(uint256).max);
  }

  /**
   * @notice Check the L1 and L2 contracts are deployed on different addresses on different triggered deployments
   */
  function test_deployOnDifferentAddresses() public {
    vm.selectFork(mainnet);
    vm.roll(block.number + 1);

    // Trigger another deployment
    (address _secondL1Adapter, address _secondL2Factory, address _secondL2Adapter) =
      l1Factory.deploy(address(OPTIMISM_L1_MESSENGER), _owner, 'Optimism', l2Deployments);
    bytes32 _secondSalt = bytes32(l1Factory.deploymentsSaltCounter());
    vm.stopPrank();

    vm.selectFork(optimism);
    IL2OpEURCDeploy.EURCInitializeData memory _eurcInitializeData = eurcInitializeData;
    _eurcInitializeData.tokenName = 'Bridged EURC (Optimism)';
    // Relay the second triggered L2 deployments message
    _relayL2Deployments(OP_ALIASED_L1_MESSENGER, _secondSalt, _secondL1Adapter, _eurcInitializeData, l2Deployments);

    // Get the eurc proxy and implementation addresses
    IEURC _secondL2Eurc = IEURC(IOpEURCBridgeAdapter(_secondL2Adapter).EURC());

    // Check the deployed addresses always differ
    assertTrue(_secondL1Adapter != address(l1Adapter));
    assertTrue(_secondL2Factory != address(l2Factory));
    assertTrue(_secondL2Adapter != address(l2Adapter));
    assertTrue(_secondL2Eurc != bridgedEURC);
  }

  /**
   * @notice Check that deployments on OP and BASE succeeds, and the contracts addresses are different
   */
  function test_deployOnMultipleL2s() public {
    // Deploy L1 Adapter and trigger the contracts deployments on OP
    vm.selectFork(mainnet);
    vm.roll(block.number + 1);

    vm.startPrank(_owner);
    (address _opL1Adapter, address _opL2Factory, address _opL2Adapter) =
      l1Factory.deploy(address(OPTIMISM_L1_MESSENGER), _owner, 'Optimism', l2Deployments);
    bytes32 _opSalt = bytes32(l1Factory.deploymentsSaltCounter());
    vm.stopPrank();

    // Check the L1 adapter was deployed
    assertGt(_opL1Adapter.code.length, 0);

    // Relay the L2 deployments on OP
    vm.selectFork(optimism);
    IL2OpEURCDeploy.EURCInitializeData memory _eurcInitializeData = eurcInitializeData;
    _eurcInitializeData.tokenName = 'Bridged EURC (Optimism)';
    _relayL2Deployments(OP_ALIASED_L1_MESSENGER, _opSalt, _opL1Adapter, _eurcInitializeData, l2Deployments);

    // Assert the contract were deployed to the expected addresses
    IEURC _opL2Eurc = IEURC(IOpEURCBridgeAdapter(_opL2Adapter).EURC());
    assertGt(_opL2Factory.code.length, 0);
    assertGt(address(_opL2Eurc).code.length, 0);
    assertGt(_opL2Eurc.implementation().code.length, 0);
    assertGt(_opL2Adapter.code.length, 0);

    // Relay the L2 deployments on BASE
    vm.selectFork(base);
    // Deploy implementation on base
    address _eurcImplAddr;
    bytes memory _EURC_IMPLEMENTATION_CREATION_CODE = EURC_IMPLEMENTATION_CREATION_CODE;
    assembly {
      _eurcImplAddr :=
        create(0, add(_EURC_IMPLEMENTATION_CREATION_CODE, 0x20), mload(_EURC_IMPLEMENTATION_CREATION_CODE))
    }
    l2Deployments.eurcImplAddr = _eurcImplAddr;

    // Go back to mainnet to trigger the deployment from L1
    vm.selectFork(mainnet);

    vm.startPrank(_owner);
    // Deploy L1 Adapter and trigger the contracts deployments on BASE
    (address _baseL1Adapter, address _baseL2Factory, address _baseL2Adapter) =
      l1Factory.deploy(address(BASE_L1_MESSENGER), _owner, 'Base', l2Deployments);
    bytes32 _baseSalt = bytes32(l1Factory.deploymentsSaltCounter());
    vm.stopPrank();

    // Check the L1 adapter was deployed
    assertGt(_baseL1Adapter.code.length, 0);

    // Back to base to relay the L2 deployments
    vm.selectFork(base);
    _eurcInitializeData.tokenName = 'Bridged EURC (Base)';
    _relayL2Deployments(BASE_ALIASED_L1_MESSENGER, _baseSalt, _baseL1Adapter, _eurcInitializeData, l2Deployments);

    // Assert the contract were deployed to the expected addresses
    IEURC _baseL2Eurc = IEURC(IOpEURCBridgeAdapter(_baseL2Adapter).EURC());
    assertGt(_baseL2Factory.code.length, 0);
    assertGt(address(_baseL2Eurc).code.length, 0);
    assertGt(_baseL2Eurc.implementation().code.length, 0);
    assertGt(_baseL2Adapter.code.length, 0);

    // Check the deployed addresses always differ (L1 adapters not checked since in case of being the same, it would
    // revert due to a colission)
    assertTrue(_opL1Adapter != _baseL1Adapter);
    assertTrue(_opL2Factory != _baseL2Factory);
    assertTrue(_opL2Adapter != _baseL2Adapter);
  }
}
