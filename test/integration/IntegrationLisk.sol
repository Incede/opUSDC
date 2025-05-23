// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {L1OpEURCBridgeAdapter} from 'contracts/L1OpEURCBridgeAdapter.sol';
import {IL1OpEURCFactory, L1OpEURCFactory} from 'contracts/L1OpEURCFactory.sol';
import {L2OpEURCBridgeAdapter} from 'contracts/L2OpEURCBridgeAdapter.sol';
import {L2OpEURCDeploy} from 'contracts/L2OpEURCDeploy.sol';
import {EURCInitTxs} from 'contracts/utils/EURCInitTxs.sol';
import {StdStorage, stdStorage} from 'forge-std/StdStorage.sol';
import {IL2OpEURCDeploy} from 'interfaces/IL2OpEURCDeploy.sol';
import {IEURC} from 'interfaces/external/IEURC.sol';
import {AddressAliasHelper} from 'test/utils/AddressAliasHelper.sol';

import {EURC_IMPLEMENTATION_CREATION_CODE} from 'test/utils/EURCImplementationCreationCode.sol';
import {Helpers} from 'test/utils/Helpers.sol';
import {ITestCrossDomainMessenger} from 'test/utils/interfaces/ITestCrossDomainMessenger.sol';

contract IntegrationLisk is Helpers {
  using stdStorage for StdStorage;

  // Constants
  uint256 internal constant _SEPOLIA_FORK_BLOCK = 8_387_900;
  uint256 internal constant _LISK_FORK_BLOCK = 21_337_100;

  IEURC public constant SEPOLIA_EURC = IEURC(0x08210F9170F89Ab7658F0B5E3fF39b0E03C594D4);
  address public constant SEPOLIA_EURC_IMPLEMENTATION = 0x76a1b9E4712E45C4c3D0ac6e2c3028ee0ce4d3b0;
  address public constant L2_CREATE2_DEPLOYER = 0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2;
  address public constant OPTIMISM_PORTAL = 0xe3d90F21490686Ec7eF37BE788E02dfC12787264;
  ITestCrossDomainMessenger public constant L2_MESSENGER =
    ITestCrossDomainMessenger(0x4200000000000000000000000000000000000007);
  ITestCrossDomainMessenger public constant LISK_L1_MESSENGER =
    ITestCrossDomainMessenger(0x857824E6234f7733ecA4e9A76804fd1afa1A3A2C);
  uint32 public constant MIN_GAS_LIMIT_DEPLOY = 9_000_000;
  uint32 internal constant _ZERO_VALUE = 0;
  uint256 internal constant _amount = 1e18;
  uint32 internal constant _MIN_GAS_LIMIT = 1_000_000;
  // The extra gas buffer added to the minimum gas limit for the relayMessage function
  uint64 internal constant _SEQUENCER_GAS_OVERHEAD = 700_000;
  uint256 internal constant _USER_NONCE = 1;
  string public constant CHAIN_NAME = 'Test';

  /// @notice Value used for the L2 sender storage slot in both the OptimismPortal and the
  ///         CrossDomainMessenger contracts before an actual sender is set. This value is
  ///         non-zero to reduce the gas cost of message passing transactions.
  address internal constant _DEFAULT_L2_SENDER = 0x000000000000000000000000000000000000dEaD;

  // solhint-disable-next-line max-line-length
  address public immutable LISK_ALIASED_L1_MESSENGER = AddressAliasHelper.applyL1ToL2Alias(address(LISK_L1_MESSENGER));

  // Fork variables
  uint256 public sepolia;
  uint256 public lisk;

  // EOA addresses
  address internal _owner = makeAddr('owner');
  address internal _user = makeAddr('user');

  // Helper variables
  bytes[] public eurcInitTxns = new bytes[](3);
  bytes public initialize;

  // OpEURC Protocol
  L1OpEURCBridgeAdapter public l1Adapter;
  L1OpEURCFactory public l1Factory;
  L2OpEURCDeploy public l2Factory;
  L2OpEURCBridgeAdapter public l2Adapter;
  IEURC public bridgedEURC;
  IL2OpEURCDeploy.EURCInitializeData public eurcInitializeData;
  IL1OpEURCFactory.L2Deployments public l2Deployments;

  function setUp() public virtual {
    sepolia = vm.createFork(vm.rpcUrl('sepolia'), _SEPOLIA_FORK_BLOCK);
    lisk = vm.createFork(vm.rpcUrl('lisk'), _LISK_FORK_BLOCK);

    l1Factory = new L1OpEURCFactory(address(SEPOLIA_EURC));

    vm.selectFork(lisk);
    address _eurcImplAddr;
    bytes memory _EURC_IMPLEMENTATION_CREATION_CODE = EURC_IMPLEMENTATION_CREATION_CODE;
    assembly {
      _eurcImplAddr :=
        create(0, add(_EURC_IMPLEMENTATION_CREATION_CODE, 0x20), mload(_EURC_IMPLEMENTATION_CREATION_CODE))
    }

    // Define the initialization transactions
    eurcInitTxns[0] = EURCInitTxs.INITIALIZEV2;
    eurcInitTxns[1] = EURCInitTxs.INITIALIZEV2_1;
    eurcInitTxns[2] = EURCInitTxs.INITIALIZEV2_2;
    // Define the L2 deployments data
    l2Deployments = IL1OpEURCFactory.L2Deployments(_owner, _eurcImplAddr, MIN_GAS_LIMIT_DEPLOY, eurcInitTxns);

    vm.selectFork(sepolia);

    vm.prank(_owner);
    (address _l1Adapter, address _l2Factory, address _l2Adapter) =
      l1Factory.deploy(address(LISK_L1_MESSENGER), _owner, CHAIN_NAME, l2Deployments);

    l1Adapter = L1OpEURCBridgeAdapter(_l1Adapter);

    // Get salt and initialize data for l2 deployments
    bytes32 _salt = bytes32(l1Factory.deploymentsSaltCounter());
    eurcInitializeData = IL2OpEURCDeploy.EURCInitializeData(
      'Bridged EURC (Test)', l1Factory.EURC_SYMBOL(), SEPOLIA_EURC.currency(), SEPOLIA_EURC.decimals()
    );

    // Give max minting power to the master minter
    address _masterMinter = SEPOLIA_EURC.masterMinter();
    vm.prank(_masterMinter);
    SEPOLIA_EURC.configureMinter(_masterMinter, type(uint256).max);

    vm.selectFork(lisk);
    _relayL2Deployments(LISK_ALIASED_L1_MESSENGER, _salt, _l1Adapter, eurcInitializeData, l2Deployments);

    l2Adapter = L2OpEURCBridgeAdapter(_l2Adapter);
    bridgedEURC = IEURC(l2Adapter.EURC());
    l2Factory = L2OpEURCDeploy(_l2Factory);

    // Make foundry know these two address exist on both forks
    vm.makePersistent(address(l1Adapter));
    vm.makePersistent(address(l2Adapter));
    vm.makePersistent(address(bridgedEURC));
    vm.makePersistent(address(l2Adapter.FALLBACK_PROXY_ADMIN()));
    vm.makePersistent(address(l2Factory));
  }

  function _relayL2Deployments(
    address _aliasedL1Messenger,
    bytes32 _salt,
    address _l1Adapter,
    IL2OpEURCDeploy.EURCInitializeData memory _eurcInitializeData,
    IL1OpEURCFactory.L2Deployments memory _l2Deployments
  ) internal {
    bytes memory _l2FactoryCArgs = abi.encode(
      _l1Adapter,
      _l2Deployments.l2AdapterOwner,
      _l2Deployments.eurcImplAddr,
      _eurcInitializeData,
      _l2Deployments.eurcInitTxs
    );
    bytes memory _l2FactoryInitCode = bytes.concat(type(L2OpEURCDeploy).creationCode, _l2FactoryCArgs);

    _relayL1ToL2Message(
      _aliasedL1Messenger,
      address(l1Factory),
      L2_CREATE2_DEPLOYER,
      _ZERO_VALUE,
      _l2Deployments.minGasLimitDeploy,
      abi.encodeWithSignature('deploy(uint256,bytes32,bytes)', _ZERO_VALUE, _salt, _l2FactoryInitCode)
    );
  }

  function _mintSupplyOnL2(uint256 _network, address _aliasedL1Messenger, uint256 _supply) internal {
    vm.selectFork(sepolia);

    // We need to do this instead of `deal` because deal doesnt change `totalSupply` state
    vm.startPrank(SEPOLIA_EURC.masterMinter());
    SEPOLIA_EURC.configureMinter(SEPOLIA_EURC.masterMinter(), _supply);
    SEPOLIA_EURC.mint(_user, _supply);
    vm.stopPrank();

    vm.startPrank(_user);
    SEPOLIA_EURC.approve(address(l1Adapter), _supply);
    l1Adapter.sendMessage(_user, _supply, _MIN_GAS_LIMIT);
    vm.stopPrank();

    vm.selectFork(_network);
    uint64 _minGasLimitMint = 1_000_000;
    _relayL1ToL2Message(
      _aliasedL1Messenger,
      address(l1Adapter),
      address(l2Adapter),
      _ZERO_VALUE,
      _minGasLimitMint,
      abi.encodeWithSignature('receiveMessage(address,address,uint256)', _user, _user, _supply)
    );
  }

  function _relayL1ToL2Message(
    address _aliasedL1Messenger,
    address _sender,
    address _target,
    uint256 _value,
    uint256 _minGasLimit,
    bytes memory _data
  ) internal {
    uint256 _messageNonce = L2_MESSENGER.messageNonce();
    vm.prank(_aliasedL1Messenger);
    // OP adds some extra gas for the relayMessage logic
    L2_MESSENGER.relayMessage{gas: _minGasLimit + _SEQUENCER_GAS_OVERHEAD}(
      _messageNonce, _sender, _target, _value, _minGasLimit, _data
    );
  }

  function _relayL2ToL1Message(
    address _sender,
    address _target,
    uint256 _value,
    uint256 _minGasLimit,
    bytes memory _data
  ) internal {
    uint256 _messageNonce = LISK_L1_MESSENGER.messageNonce();

    // For simplicity we do this as this slot is not exposed until prove and finalize is done
    stdstore.target(OPTIMISM_PORTAL).sig('l2Sender()').checked_write(address(L2_MESSENGER));
    vm.prank(OPTIMISM_PORTAL);
    // OP adds some extra gas for the relayMessage logic
    LISK_L1_MESSENGER.relayMessage{gas: _minGasLimit + _SEQUENCER_GAS_OVERHEAD}(
      _messageNonce, _sender, _target, _value, _minGasLimit, _data
    );
    // Needs to be reset to mimic production
    stdstore.target(OPTIMISM_PORTAL).sig('l2Sender()').checked_write(_DEFAULT_L2_SENDER);
  }
}

contract IntegrationSetup is IntegrationLisk {
  /**
   * @notice Ensure the setup is correct
   */
  function testSetup() public {
    vm.selectFork(sepolia);
    assertEq(l1Adapter.LINKED_ADAPTER(), address(l2Adapter));

    vm.selectFork(lisk);
    assertEq(l2Adapter.LINKED_ADAPTER(), address(l1Adapter));
    assertEq(l2Adapter.FALLBACK_PROXY_ADMIN().owner(), address(l2Adapter));
  }
}
