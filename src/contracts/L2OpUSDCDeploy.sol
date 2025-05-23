// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import {L2OpEURCBridgeAdapter} from 'contracts/L2OpEURCBridgeAdapter.sol';
import {EURC_PROXY_CREATION_CODE} from 'contracts/utils/EURCProxyCreationCode.sol';
import {IL2OpEURCDeploy} from 'interfaces/IL2OpEURCDeploy.sol';
import {IEURC} from 'interfaces/external/IEURC.sol';
import {OpEURCBridgeAdapter} from 'src/contracts/universal/OpEURCBridgeAdapter.sol';

/**
 * @title L2OpEURCDeploy
 * @notice Deployer contract for deploying the L2 EURC implementation, proxy, and `L2OpEURCBridgeAdapter` contract,
 * all at once on the `deploy` function.
 * @dev The salt is always different for each deployed instance of this contract on the L1 Factory, and the L2 contracts
 * are deployed with `CREATE` to guarantee that the addresses are unique among all the L2s, so we avoid a scenario where
 * L2 contracts have the same address on different L2s when triggered by different owners.
 */
contract L2OpEURCDeploy is IL2OpEURCDeploy {
  address internal constant _L2_MESSENGER = 0x4200000000000000000000000000000000000007;

  /**
   * @notice Deploys the EURC implementation, proxy, and L2 adapter contracts all at once, and then initializes the EURC
   * @param _l1Adapter The address of the L1 adapter contract
   * @param _l2AdapterOwner The address of the L2 adapter owner
   * @param _eurcImplAddr The address of the EURC implementation on L2 to connect the proxy to
   * @param _eurcInitializeData The EURC name, symbol, currency, and decimals used on the first `initialize()` call
   * @param _eurcInitTxs The initialization transactions for the EURC proxy and implementation contracts
   * @dev The EURC proxy owner needs to be set on the first init tx, and will be set to the L2 adapter address
   * @dev Using `CREATE` to guarantee that the addresses are unique among all the L2s
   */
  constructor(
    address _l1Adapter,
    address _l2AdapterOwner,
    address _eurcImplAddr,
    EURCInitializeData memory _eurcInitializeData,
    bytes[] memory _eurcInitTxs
  ) {
    // Deploy EURC proxy
    bytes memory _eurcProxyCArgs = abi.encode(_eurcImplAddr);
    bytes memory _eurcProxyInitCode = bytes.concat(EURC_PROXY_CREATION_CODE, _eurcProxyCArgs);

    // 1st nonce
    address _eurcProxy = _deployCreate(_eurcProxyInitCode);
    emit EURCProxyDeployed(_eurcProxy);

    // Deploy L2 Adapter implementation and proxy, initializing it with the owner
    // 2nd nonce
    address _l2AdapterImpl = address(new L2OpEURCBridgeAdapter(_eurcProxy, _L2_MESSENGER, _l1Adapter));

    // 3rd nonce
    address _l2Adapter =
      address(new ERC1967Proxy(_l2AdapterImpl, abi.encodeCall(OpEURCBridgeAdapter.initialize, _l2AdapterOwner)));
    emit L2AdapterDeployed(_l2Adapter);

    // Deploy the FallbackProxyAdmin internally in the L2 Adapter to keep it unique
    address _fallbackProxyAdmin = address(L2OpEURCBridgeAdapter(_l2Adapter).FALLBACK_PROXY_ADMIN());
    // Change the EURC admin so the init txs can be executed over the proxy from this contract
    IEURC(_eurcProxy).changeAdmin(_fallbackProxyAdmin);

    // Execute the EURC initialization transactions over the EURC proxy
    _executeInitTxs(_eurcProxy, _eurcInitializeData, _l2Adapter, _eurcInitTxs);
  }

  /**
   * @notice Executes the initialization transactions for a target contract
   * @param _eurc The address of the contract to execute the transactions on
   * @param _eurcInitializeData The EURC name, symbol, currency, and decimals used on the first `initialize()` call
   * @param _l2Adapter The address of the L2 adapter
   * @param _initTxs The initialization transactions to execute
   * @dev The first `initialize()` call is defined here to ensure it is properly done, granting the right permissions
   * to the L2 adapter contract. The L2 factory is set as master minter first so it can configure the l2 adapter as
   * unlimited minter and then the master minter is updated again to the l2 adapter
   */
  function _executeInitTxs(
    address _eurc,
    EURCInitializeData memory _eurcInitializeData,
    address _l2Adapter,
    bytes[] memory _initTxs
  ) internal {
    // Initialize the EURC contract
    IEURC(_eurc).initialize(
      _eurcInitializeData.tokenName,
      _eurcInitializeData.tokenSymbol,
      _eurcInitializeData.tokenCurrency,
      _eurcInitializeData.tokenDecimals,
      address(this),
      _l2Adapter,
      _l2Adapter,
      address(this)
    );

    // Add l2 adapter as unlimited minter
    IEURC(_eurc).configureMinter(_l2Adapter, type(uint256).max);
    // Set l2 adapter as new master minter
    IEURC(_eurc).updateMasterMinter(_l2Adapter);
    // Transfer EURC ownership to the L2 adapter
    IEURC(_eurc).transferOwnership(_l2Adapter);

    // Execute the input init txs, use `_i+1` as revert argument since the first tx is already executed on the contract
    for (uint256 _i; _i < _initTxs.length; _i++) {
      (bool _success,) = _eurc.call(_initTxs[_i]);
      if (!_success) {
        revert IL2OpEURCDeploy_InitializationFailed(_i + 1);
      }
    }
  }

  /**
   * @notice Deploys a new contract via calling the `CREATE` opcode
   * @param _initCode The creation bytecode.
   * @return _newContract The 20-byte address where the contract was deployed.
   */
  function _deployCreate(bytes memory _initCode) internal returns (address _newContract) {
    assembly ("memory-safe") {
      _newContract := create(0x0, add(_initCode, 0x20), mload(_initCode))
    }
    if (_newContract == address(0) || _newContract.code.length == 0) {
      revert IL2OpEURCDeploy_DeploymentFailed();
    }
  }
}
