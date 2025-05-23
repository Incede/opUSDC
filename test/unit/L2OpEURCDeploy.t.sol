// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ERC1967Utils} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol';
import {L2OpEURCDeploy} from 'contracts/L2OpEURCDeploy.sol';
import {EURC_PROXY_CREATION_CODE} from 'contracts/utils/EURCProxyCreationCode.sol';
import {Test} from 'forge-std/Test.sol';
import {IL2OpEURCDeploy} from 'interfaces/IL2OpEURCDeploy.sol';
import {IOpEURCBridgeAdapter} from 'interfaces/IOpEURCBridgeAdapter.sol';
import {IEURC} from 'interfaces/external/IEURC.sol';
import {Helpers} from 'test/utils/Helpers.sol';

contract L2OpEURCDeployForTest is L2OpEURCDeploy {
  constructor(
    address _l1Adapter,
    address _l2AdapterOwner,
    address _eurcImplAddr,
    EURCInitializeData memory _eurcInitializeData,
    bytes[] memory _eurcInitTxs
  ) L2OpEURCDeploy(_l1Adapter, _l2AdapterOwner, _eurcImplAddr, _eurcInitializeData, _eurcInitTxs) {}

  function forTest_deployCreate(bytes memory _initCode) public returns (address _newContract) {
    _newContract = _deployCreate(_initCode);
  }

  function forTest_executeInitTxs(
    address _eurc,
    EURCInitializeData memory _eurcInitializeData,
    address _l2Adapter,
    bytes[] memory _initTxs
  ) public {
    _executeInitTxs(_eurc, _eurcInitializeData, _l2Adapter, _initTxs);
  }
}

contract Base is Test, Helpers {
  L2OpEURCDeployForTest public factory;

  address internal _l2Messenger = 0x4200000000000000000000000000000000000007;
  address internal _l1Factory = makeAddr('l1Factory');
  address internal _messenger = makeAddr('messenger');
  address internal _create2Deployer = makeAddr('create2Deployer');
  address internal _l1Adapter = makeAddr('l1Adapter');
  address internal _l2AdapterOwner = makeAddr('l2AdapterOwner');
  address internal _eurcImplAddr = makeAddr('eurcImpl');
  uint256 internal _eurcProxyDeploymentNonce = 1;
  uint256 internal _l2AdapterDeploymentNonce = 3;

  address internal _dummyContract;

  IL2OpEURCDeploy.EURCInitializeData internal _eurcInitializeData;
  bytes[] internal _emptyInitTxs;
  bytes[] internal _initTxsEurc;
  bytes[] internal _badInitTxs;

  function setUp() public virtual {
    // Precalculate the factory address. The real create 2 deployer will do it through `CREATE2`, but we'll use `CREATE`
    // just for scope of the unit tests
    uint256 _deployerNonce = vm.getNonce(_create2Deployer);
    factory = L2OpEURCDeployForTest(_precalculateCreateAddress(_create2Deployer, _deployerNonce));

    // Set the initialize data
    _eurcInitializeData = IL2OpEURCDeploy.EURCInitializeData({
      tokenName: 'USD Coin',
      tokenSymbol: 'EURC',
      tokenCurrency: 'USD',
      tokenDecimals: 6
    });

    // Set the init txs for the EURC implementation contract (DummyContract)
    bytes memory _initTxOne = abi.encodeWithSignature('returnTrue()');
    bytes memory _initTxTwo = abi.encodeWithSignature('returnFalse()');
    bytes memory _initTxThree = abi.encodeWithSignature('returnOne()');
    _initTxsEurc = new bytes[](3);
    _initTxsEurc[0] = _initTxOne;
    _initTxsEurc[1] = _initTxTwo;
    _initTxsEurc[2] = _initTxThree;

    // Set the bad init transaction to test when the initialization fails
    bytes memory _badInitTx = abi.encodeWithSignature('nonExistentFunction()');
    _badInitTxs = new bytes[](2);
    _badInitTxs[0] = '';
    _badInitTxs[1] = _badInitTx;

    vm.etch(_eurcImplAddr, type(ForTestDummyContract).runtimeCode);
  }
}

contract L2OpEURCDeploy_Unit_Constructor is Base {
  using ERC1967Utils for address;

  event EURCImplementationDeployed(address _l2EurcImplementation);
  event EURCProxyDeployed(address _l2EurcProxy);
  event L2AdapterDeployed(address _l2Adapter);

  /**
   * @notice Check the deployment of the L2 adapter implementation and proxy is properly done by checking the emitted
   * event and the implementation length
   * @dev Assuming the EURC proxy correctly sets the implementation address to check it was properly deployed
   */
  function test_deployEurcProxy() public {
    // Calculate the eurc proxy address
    address _eurcProxy = _precalculateCreateAddress(address(factory), _eurcProxyDeploymentNonce);

    // Expect the EURC proxy deployment event to be properly emitted
    vm.expectEmit(true, true, true, true);
    emit EURCProxyDeployed(_eurcProxy);

    // Execute
    vm.prank(_create2Deployer);
    new L2OpEURCDeploy(_l1Adapter, _l2AdapterOwner, _eurcImplAddr, _eurcInitializeData, _emptyInitTxs);

    // Assert the EURC proxy was deployed
    assertGt(_eurcProxy.code.length, 0, 'EURC proxy was not deployed');
    assertEq(IEURC(_eurcProxy).implementation(), _eurcImplAddr, 'EURC implementation was not set');
  }

  /**
   * @notice Check the deployment of the L2 adapter implementation and proxy is properly done by checking the address
   * on the emitted, the code length of the contract and the constructor values were properly set
   * @dev Assuming the adapter correctly sets the immutables to check the constructor values were properly set
   */
  function test_deployAdapter() public {
    // Calculate the eurc proxy address
    address _eurcProxy = _precalculateCreateAddress(address(factory), _eurcProxyDeploymentNonce);

    // Calculate the l2 adapter proxy address
    address _l2AdapterProxy = _precalculateCreateAddress(address(factory), _l2AdapterDeploymentNonce);

    // Expect the adapter deployment event to be properly emitted
    vm.expectEmit(true, true, true, true);
    emit L2AdapterDeployed(_l2AdapterProxy);

    // Execute
    vm.prank(_create2Deployer);
    new L2OpEURCDeploy(_l1Adapter, _l2AdapterOwner, _eurcImplAddr, _eurcInitializeData, _emptyInitTxs);

    // Assert the adapter was deployed
    assertGt(_l2AdapterProxy.code.length, 0, 'L2 adapter was not deployed');
    // Check the constructor values were properly passed
    assertEq(IOpEURCBridgeAdapter(_l2AdapterProxy).EURC(), _eurcProxy, 'EURC proxy was not set');
    assertEq(IOpEURCBridgeAdapter(_l2AdapterProxy).MESSENGER(), _l2Messenger, 'L2 messenger was not set');
    assertEq(IOpEURCBridgeAdapter(_l2AdapterProxy).LINKED_ADAPTER(), _l1Adapter, 'L1 factory was not set');
    assertEq(Ownable(_l2AdapterProxy).owner(), _l2AdapterOwner, 'L2 adapter owner was not set');
  }

  /**
   * @notice Check the `changeAdmin` function is called on the EURC proxy with the proper fallback proxy admin address
   */
  function test_callChangeAdminWithFallbackProxy() public {
    // Calculate the eurc proxy address
    address _eurcProxy = _precalculateCreateAddress(address(factory), _eurcProxyDeploymentNonce);

    // Calculate the l2 adapter address
    address _l2Adapter = _precalculateCreateAddress(address(factory), _l2AdapterDeploymentNonce);

    // Calculate the fallback proxy admin address
    uint256 _fallbackProxyAdminNonce = 1;
    address _fallbackProxyAdmin = _precalculateCreateAddress(_l2Adapter, _fallbackProxyAdminNonce);

    // Expect the call over 'changeAdmin' function
    vm.expectCall(_eurcProxy, abi.encodeWithSelector(IEURC.changeAdmin.selector, _fallbackProxyAdmin));

    // Execute
    vm.prank(_create2Deployer);
    new L2OpEURCDeploy(_l1Adapter, _l2AdapterOwner, _eurcImplAddr, _eurcInitializeData, _emptyInitTxs);
  }

  /**
   * @notice Check init txs are properly executed over the L2 adapter implementation and proxy, and that the
   * `changeAdmin` function is called on it too.
   */
  function test_executeEurcProxyInitTxs() public {
    // Calculate the eurc proxy address
    address _eurcProxy = _precalculateCreateAddress(address(factory), _eurcProxyDeploymentNonce);

    // Expect the init txs to be called
    vm.expectCall(_eurcProxy, _initTxsEurc[0]);
    vm.expectCall(_eurcProxy, _initTxsEurc[1]);

    // Execute
    vm.prank(_create2Deployer);
    new L2OpEURCDeploy(_l1Adapter, _l2AdapterOwner, _eurcImplAddr, _eurcInitializeData, _initTxsEurc);
  }
}

contract L2OpEURCDeploy_Unit_ExecuteInitTxs is Base {
  /**
   * @notice Deploy the factory to test the internal function
   */
  function setUp() public override {
    super.setUp();

    vm.prank(_create2Deployer);
    new L2OpEURCDeployForTest(_l1Adapter, _l2AdapterOwner, _eurcImplAddr, _eurcInitializeData, _emptyInitTxs);
  }

  /**
   * @notice Check `initialize()` is properly called
   */
  function test_callInitialize(address _l2Adapter) public {
    // Mock the call over the functions
    _mockExecuteTxsCalls();

    // Expect `initialize` to be properly called
    vm.expectCall(
      address(factory),
      abi.encodeWithSelector(
        IEURC.initialize.selector,
        _eurcInitializeData.tokenName,
        _eurcInitializeData.tokenSymbol,
        _eurcInitializeData.tokenCurrency,
        _eurcInitializeData.tokenDecimals,
        address(factory),
        _l2Adapter,
        _l2Adapter,
        address(factory)
      )
    );

    // Execute
    factory.forTest_executeInitTxs(address(factory), _eurcInitializeData, _l2Adapter, _emptyInitTxs);
  }

  /**
   * @notice Check `configureMinter()` is properly called
   */
  function test_callConfigureMinter(address _l2Adapter) public {
    // Mock the call over the functions
    _mockExecuteTxsCalls();

    // Expect `configureMinter` to be properly called
    // solhint-disable-next-line max-line-length
    vm.expectCall(
      address(factory), abi.encodeWithSelector(IEURC.configureMinter.selector, _l2Adapter, type(uint256).max)
    );

    // Execute
    factory.forTest_executeInitTxs(address(factory), _eurcInitializeData, _l2Adapter, _emptyInitTxs);
  }

  /**
   * @notice Check `updateMasterMinter()` is properly called
   */
  function test_callUpdateMasterMinter(address _l2Adapter) public {
    // Mock the call over the functions
    _mockExecuteTxsCalls();

    // Expect `updateMasterMinter` to be properly called
    vm.expectCall(address(factory), abi.encodeWithSelector(IEURC.updateMasterMinter.selector, _l2Adapter));

    // Execute
    factory.forTest_executeInitTxs(address(factory), _eurcInitializeData, _l2Adapter, _emptyInitTxs);
  }

  /**
   * @notice Check `transferOwnership()` is properly called
   */
  function test_callTransferOwnership(address _l2Adapter) public {
    // Mock the call over the functions
    _mockExecuteTxsCalls();

    // Expect `transferOwnership` to be properly called
    vm.expectCall(address(factory), abi.encodeWithSelector(IEURC.transferOwnership.selector, _l2Adapter));

    // Execute
    factory.forTest_executeInitTxs(address(factory), _eurcInitializeData, _l2Adapter, _emptyInitTxs);
  }

  /**
   * @notice Check the execution of the initialization transactions over a target contract
   */
  function test_executeInitTxsArray(address _l2Adapter) public {
    _mockExecuteTxsCalls();

    // Mock the call to the target contract
    _mockAndExpect(address(factory), _initTxsEurc[0], '');
    _mockAndExpect(address(factory), _initTxsEurc[1], '');
    _mockAndExpect(address(factory), _initTxsEurc[2], '');

    // Execute the initialization transactions
    factory.forTest_executeInitTxs(address(factory), _eurcInitializeData, _l2Adapter, _initTxsEurc);
  }

  /**
   * @notice Check it properly reverts if the initialization transactions fail
   */
  function test_revertIfInitTxsOnArrayFail(address _l2Adapter) public {
    _mockExecuteTxsCalls();

    bytes[] memory _badInitTxs = _initTxsEurc;
    for (uint256 _i; _i < _badInitTxs.length; _i++) {
      // Mock the calls
      vm.mockCall(address(factory), _badInitTxs[0], abi.encode(true));
      vm.mockCall(address(factory), _badInitTxs[1], abi.encode(false));
      vm.mockCall(address(factory), _badInitTxs[2], abi.encode(1));

      // Mock a revert only on the call corresponding to the for loop index
      vm.mockCallRevert(address(factory), _badInitTxs[_i], '');

      // Expect it to revert with the right index as argument
      vm.expectRevert(abi.encodeWithSelector(IL2OpEURCDeploy.IL2OpEURCDeploy_InitializationFailed.selector, _i + 1));
      // Execute
      factory.forTest_executeInitTxs(address(factory), _eurcInitializeData, _l2Adapter, _badInitTxs);
    }
  }

  function _mockExecuteTxsCalls() internal {
    // Mock call over `initialize()` function
    vm.mockCall(address(factory), abi.encodeWithSelector(IEURC.initialize.selector), '');

    // Mock the call over `configureMinter()` function
    vm.mockCall(address(factory), abi.encodeWithSelector(IEURC.configureMinter.selector), abi.encode(true));

    // Mock the call over `updateMasterMinter()` function
    vm.mockCall(address(factory), abi.encodeWithSelector(IEURC.updateMasterMinter.selector), '');

    // Mock the call over `transferOwnership()` function
    vm.mockCall(address(factory), abi.encodeWithSelector(IEURC.transferOwnership.selector), '');
  }
}

contract L2OpEURCDeploy_Unit_DeployCreate is Base {
  /**
   * @notice Deploy the factory to test the internal function
   */
  function setUp() public override {
    super.setUp();

    vm.prank(_create2Deployer);
    new L2OpEURCDeployForTest(_l1Adapter, _l2AdapterOwner, _eurcImplAddr, _eurcInitializeData, _emptyInitTxs);
  }

  /**
   * @notice Check the deployment of a contract using the `CREATE2` opcode is properly done to the expected addrtess
   */
  function test_deployCreate() public {
    // Get the init code with the EURC proxy creation code plus the EURC implementation address
    bytes memory _initCode = bytes.concat(EURC_PROXY_CREATION_CODE, abi.encode(address(factory)));

    // Precalculate the address of the contract that will be deployed with the current factory's nonce
    uint256 _deploymentNonce = vm.getNonce(address(factory));
    address _expectedAddress = _precalculateCreateAddress(address(factory), _deploymentNonce);

    // Execute
    (address _newContract) = factory.forTest_deployCreate(_initCode);

    // Assert the deployed was deployed at the correct address and contract has code
    assertEq(_newContract, _expectedAddress);
    assertGt(_newContract.code.length, 0);
  }

  /**
   * @notice Check it reverts if the deployment fails
   */
  function test_revertIfDeploymentFailed() public {
    // Create a bad format for the init code to make the deployment revert
    bytes memory _badInitCode = '0x0000405060';

    // Expect the tx to revert
    vm.expectRevert(IL2OpEURCDeploy.IL2OpEURCDeploy_DeploymentFailed.selector);

    // Execute
    factory.forTest_deployCreate(_badInitCode);
  }
}

/**
 * @notice Dummy contract used only for testing purposes
 * @dev Need to create a dummy contract and get its bytecode because you can't mock a call over a contract that's not
 * deployed yet, so the unique alternative is to call the contract properly.
 */
contract ForTestDummyContract {
  constructor() {}

  function initialize(
    string memory _tokenName,
    string memory _tokenSymbol,
    string memory _tokenCurrency,
    uint8 _tokenDecimals,
    address _newMasterMinter,
    address _newPauser,
    address _newBlacklister,
    address _newOwner
  ) external {}

  function configureMinter(address, uint256) external returns (bool) {}

  function updateMasterMinter(address) external {}

  function transferOwnership(address) external {}

  function returnTrue() public pure returns (bool) {
    return true;
  }

  function returnFalse() public pure returns (bool) {
    return true;
  }

  function returnOne() public pure returns (uint256) {
    return 1;
  }
}
