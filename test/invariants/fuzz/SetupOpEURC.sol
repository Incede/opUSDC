// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {EchidnaTest} from '../AdvancedTestsUtils.sol';
// https://github.com/crytic/building-secure-contracts/blob/master/program-analysis/echidna/advanced/testing-bytecode.md
import {L1OpEURCBridgeAdapter} from 'contracts/L1OpEURCBridgeAdapter.sol';
import {IL1OpEURCFactory, L1OpEURCFactory} from 'contracts/L1OpEURCFactory.sol';
import {L2OpEURCBridgeAdapter} from 'contracts/L2OpEURCBridgeAdapter.sol';
import {IL2OpEURCDeploy, L2OpEURCDeploy} from 'contracts/L2OpEURCDeploy.sol';
import {EURCInitTxs} from 'contracts/utils/EURCInitTxs.sol';
import {IEURC} from 'interfaces/external/IEURC.sol';
import {Create2Deployer} from 'test/invariants/fuzz/Create2Deployer.sol';
import {MockBridge} from 'test/invariants/fuzz/MockBridge.sol';
import {MockPortal} from 'test/invariants/fuzz/MockPortal.sol';
import {EURC_IMPLEMENTATION_CREATION_CODE} from 'test/utils/EURCImplementationCreationCode.sol';

// solhint-disable
contract SetupOpEURC is EchidnaTest {
  string public constant CHAIN_NAME = 'Optimism';
  string internal constant _NAME = 'OpEURCBridgeAdapter';
  string internal constant _VERSION = '1.0.0';

  IEURC eurcMainnet;
  IEURC eurcBridged;

  bytes32 internal _salt = keccak256(abi.encode(address(this)));
  address internal eurcBridgedImplementation;

  L1OpEURCBridgeAdapter internal l1Adapter;
  L1OpEURCFactory internal factory;

  L2OpEURCBridgeAdapter internal l2Adapter;
  L2OpEURCDeploy internal l2Factory;

  MockBridge internal mockMessenger;
  MockPortal internal mockPortal;
  Create2Deployer internal create2Deployer;

  address internal _eurcMinter = address(uint160(uint256(keccak256('eurc.minter'))));

  /////////////////////////////////////////////////////////////////////
  //                          Initial setup                          //
  /////////////////////////////////////////////////////////////////////

  constructor() {
    IL1OpEURCFactory.L2Deployments memory _l2Deployments = _mainnetSetup();
    _l2Setup(_l2Deployments);
    _setupEurc();
  }

  function _setupEurc() internal {
    hevm.prank(eurcMainnet.masterMinter());
    eurcMainnet.configureMinter(address(_eurcMinter), type(uint256).max);

    hevm.prank(eurcMainnet.masterMinter());
    eurcMainnet.configureMinter(address(l1Adapter), type(uint256).max); // Allow burning the locked supplye
  }

  // Deploy: EURC L1, factory L1, L1 adapter
  function _mainnetSetup() internal returns (IL1OpEURCFactory.L2Deployments memory _l2Deployments) {
    address targetAddress;

    uint256 size = EURC_IMPLEMENTATION_CREATION_CODE.length;
    bytes memory _eurcBytecode = EURC_IMPLEMENTATION_CREATION_CODE;

    // Deploy EURC on "mainnet"
    assembly {
      targetAddress := create(0, add(_eurcBytecode, 0x20), size) // Skip the 32 bytes encoded length.
    }

    eurcMainnet = IEURC(targetAddress);

    bytes[] memory eurcInitTxns = new bytes[](3);
    eurcInitTxns[0] = EURCInitTxs.INITIALIZEV2;
    eurcInitTxns[1] = EURCInitTxs.INITIALIZEV2_1;
    eurcInitTxns[2] = EURCInitTxs.INITIALIZEV2_2;

    factory = new L1OpEURCFactory(address(eurcMainnet));

    // Deploy EURC implementation on L2
    assembly {
      targetAddress := create(0, add(_eurcBytecode, 0x20), size) // Skip the 32 bytes encoded length.
    }

    eurcBridgedImplementation = targetAddress;

    mockMessenger = MockBridge(0x4200000000000000000000000000000000000007);
    mockPortal = new MockPortal();
    mockMessenger.setPortalAddress(address(mockPortal));

    // owner is this contract, as managed in the _agents handler
    _l2Deployments = IL1OpEURCFactory.L2Deployments(address(this), eurcBridgedImplementation, 9_000_000, eurcInitTxns);

    (address _l1Adapter, address _l2Factory, address _l2Adapter) =
      factory.deploy(address(mockMessenger), address(this), CHAIN_NAME, _l2Deployments);

    l2Factory = L2OpEURCDeploy(_l2Factory);
    l1Adapter = L1OpEURCBridgeAdapter(_l1Adapter);
    l2Adapter = L2OpEURCBridgeAdapter(_l2Adapter);
  }

  // Send a (mock) message to the L2 messenger to deploy the L2 factory and the L2 adapter (which deploys eurc L2 too)
  function _l2Setup(IL1OpEURCFactory.L2Deployments memory _l2Deployments) internal {
    IL2OpEURCDeploy.EURCInitializeData memory eurcInitializeData = IL2OpEURCDeploy.EURCInitializeData(
      string.concat(factory.EURC_NAME(), ' ', '(', CHAIN_NAME, ')'),
      factory.EURC_SYMBOL(),
      eurcMainnet.currency(),
      eurcMainnet.decimals()
    );

    bytes memory _l2factoryConstructorArgs = abi.encode(
      address(l1Adapter),
      _l2Deployments.l2AdapterOwner,
      _l2Deployments.eurcImplAddr,
      eurcInitializeData, // encode?
      _l2Deployments.eurcInitTxs // encodePacked?
    );

    bytes memory _l2FactoryInitCode = bytes.concat(type(L2OpEURCDeploy).creationCode, _l2factoryConstructorArgs);

    // !!!! Nonce incremented to avoid collision !!!
    mockMessenger.relayMessage(
      mockMessenger.messageNonce() + 1,
      address(factory),
      factory.L2_CREATE2_DEPLOYER(),
      0,
      9_000_000,
      abi.encodeWithSignature('deploy(uint256,bytes32,bytes)', 0, factory.deploymentsSaltCounter(), _l2FactoryInitCode)
    );

    eurcBridged = IEURC(l2Adapter.EURC());
  }
}
