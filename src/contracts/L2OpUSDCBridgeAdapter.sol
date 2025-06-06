// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {OpUSDCBridgeAdapter} from 'contracts/universal/OpUSDCBridgeAdapter.sol';
import {FallbackProxyAdmin} from 'contracts/utils/FallbackProxyAdmin.sol';
import {IL1OpUSDCBridgeAdapter} from 'interfaces/IL1OpUSDCBridgeAdapter.sol';
import {IL2OpUSDCBridgeAdapter} from 'interfaces/IL2OpUSDCBridgeAdapter.sol';
import {IOpUSDCBridgeAdapter} from 'interfaces/IOpUSDCBridgeAdapter.sol';
import {ICrossDomainMessenger} from 'interfaces/external/ICrossDomainMessenger.sol';
import {IUSDC} from 'interfaces/external/IUSDC.sol';

/**
 * @title L2OpUSDCBridgeAdapter
 * @notice L2OpUSDCBridgeAdapter is a contract that bridges Bridged USDC from L2 to L1 and and receives the it from L1.
 * It finalizes the migration process of bridged USDC to native USDC on L2 after being triggered by the L1 adapter, and
 * sends the amount to be burned back to the L1 adapter to finish the migration process.
 * @dev The owner of this contract is capable of calling any USDC function, except the ownership or admin ones.
 */
contract L2OpUSDCBridgeAdapter is IL2OpUSDCBridgeAdapter, OpUSDCBridgeAdapter {
  using SafeERC20 for IUSDC;

  ///@notice `transferOwnership(address)` USDC function selector
  bytes4 internal constant _TRANSFER_OWNERSHIP_SELECTOR = 0xf2fde38b;
  ///@notice `changeAdmin(address)` USDC function selector
  bytes4 internal constant _CHANGE_ADMIN_SELECTOR = 0x8f283970;
  ///@notice `upgradeTo(address)` USDC function selector
  bytes4 internal constant _UPGRADE_TO_SELECTOR = 0x3659cfe6;
  ///@notice `upgradeToAndCall(address,bytes)` USDC function selector
  bytes4 internal constant _UPGRADE_TO_AND_CALL_SELECTOR = 0x4f1ef286;
  ///@notice `updateMasterMinter(address)` USDC function selector
  bytes4 internal constant _UPDATE_MASTER_MINTER_SELECTOR = 0xaa20e1e4;

  /// @inheritdoc IL2OpUSDCBridgeAdapter
  // solhint-disable-next-line var-name-mixedcase
  FallbackProxyAdmin public FALLBACK_PROXY_ADMIN;

  /// @inheritdoc IL2OpUSDCBridgeAdapter
  address public roleCaller;

  /// @notice Reserve 50 more storage slots to be safe on future upgrades
  uint256[50] private __gap;

  /**
   * @notice Construct the OpUSDCBridgeAdapter contract
   * @param _usdc The address of the USDC Contract to be used by the adapter
   * @param _messenger The address of the messenger contract
   * @param _linkedAdapter The address of the linked adapter
   * @dev The constructor is only used to initialize the OpUSDCBridgeAdapter immutable variables
   */
  /* solhint-disable no-unused-vars */
  constructor(
    address _usdc,
    address _messenger,
    address _linkedAdapter
  ) OpUSDCBridgeAdapter(_usdc, _messenger, _linkedAdapter) {}
  /* solhint-enable no-unused-vars */

  /**
   * @notice Sets the owner of the contract
   * @param _owner The address of the owner
   * @dev This function needs only used during the deployment of the proxy contract, and it is disabled for the
   * implementation contract
   */
  function initialize(address _owner) external virtual override initializer {
    __Ownable_init(_owner);
    string memory _name = 'OpUSDCBridgeAdapter';
    string memory _version = '1.0.0';
    __EIP712_init(_name, _version);
    FALLBACK_PROXY_ADMIN = new FallbackProxyAdmin(USDC);
  }

  /*///////////////////////////////////////////////////////////////
                              MIGRATION
  ///////////////////////////////////////////////////////////////*/

  /**
   * @notice Initiates the process to migrate the bridged USDC to native USDC
   * @dev Full migration can't finish until L1 receives the message for setting the burn amount
   * @param _roleCaller The address that will be allowed to transfer the USDC roles
   * @param _setBurnAmountMinGasLimit Minimum gas limit that the setBurnAmount message can be executed on L1
   */
  function receiveMigrateToNative(address _roleCaller, uint32 _setBurnAmountMinGasLimit) external onlyLinkedAdapter {
    messengerStatus = Status.Deprecated;
    roleCaller = _roleCaller;

    uint256 _burnAmount = IUSDC(USDC).totalSupply();

    // Remove the L2 Adapter as a minter
    IUSDC(USDC).removeMinter(address(this));

    ICrossDomainMessenger(MESSENGER).sendMessage(
      LINKED_ADAPTER, abi.encodeCall(IL1OpUSDCBridgeAdapter.setBurnAmount, (_burnAmount)), _setBurnAmountMinGasLimit
    );

    emit MigratingToNative(MESSENGER, _roleCaller);
  }

  /**
   * @notice Transfers the USDC roles to the new owner
   * @param _owner The address to transfer ownership to
   * @dev Can only be called by the role caller set in the migration process
   */
  function transferUSDCRoles(address _owner) external {
    if (msg.sender != roleCaller) revert IOpUSDCBridgeAdapter_InvalidCaller();

    // Transfer ownership of the USDC contract to circle
    IUSDC(USDC).transferOwnership(_owner);

    // Transfer proxy admin ownership to the caller
    FALLBACK_PROXY_ADMIN.changeAdmin(msg.sender);
  }

  /*///////////////////////////////////////////////////////////////
                          MESSAGING CONTROL
  ///////////////////////////////////////////////////////////////*/

  /**
   * @notice Receive the stop messaging message from the linked adapter and stop outgoing messages
   */
  function receiveStopMessaging() external onlyLinkedAdapter {
    if (messengerStatus == Status.Deprecated) revert IOpUSDCBridgeAdapter_MessagingDisabled();

    messengerStatus = Status.Paused;

    emit MessagingStopped(MESSENGER);
  }

  /**
   * @notice Resume messaging after it was stopped
   */
  function receiveResumeMessaging() external onlyLinkedAdapter {
    if (messengerStatus == Status.Deprecated) revert IOpUSDCBridgeAdapter_MessagingDisabled();

    messengerStatus = Status.Active;

    emit MessagingResumed(MESSENGER);
  }

  /*///////////////////////////////////////////////////////////////
                             MESSAGING
  ///////////////////////////////////////////////////////////////*/

  /**
   * @notice Send tokens to another chain through the linked adapter
   * @param _to The target address on the destination chain
   * @param _amount The amount of tokens to send
   * @param _minGasLimit Minimum gas limit that the message can be executed with
   */
  function sendMessage(address _to, uint256 _amount, uint32 _minGasLimit) external override {
    if (_to == address(0)) revert IOpUSDCBridgeAdapter_InvalidAddress();
    // Ensure the address is not blacklisted
    if (IUSDC(USDC).isBlacklisted(_to)) revert IOpUSDCBridgeAdapter_BlacklistedAddress();

    // Ensure messaging is enabled
    if (messengerStatus != Status.Active) revert IOpUSDCBridgeAdapter_MessagingDisabled();

    _sendMessage(msg.sender, _to, _amount, _minGasLimit);
  }

  /**
   * @notice Send signer tokens to another chain through the linked adapter
   * @param _signer The address of the user sending the message
   * @param _to The target address on the destination chain
   * @param _amount The amount of tokens to send
   * @param _signature The signature of the user
   * @param _nonce The nonce of the user
   * @param _deadline The deadline for the message to be executed
   * @param _minGasLimit Minimum gas limit that the message can be executed with
   */
  function sendMessage(
    address _signer,
    address _to,
    uint256 _amount,
    bytes calldata _signature,
    uint256 _nonce,
    uint256 _deadline,
    uint32 _minGasLimit
  ) external override {
    if (_to == address(0)) revert IOpUSDCBridgeAdapter_InvalidAddress();
    // Ensure the address is not blacklisted
    if (IUSDC(USDC).isBlacklisted(_to)) revert IOpUSDCBridgeAdapter_BlacklistedAddress();

    // Ensure messaging is enabled
    if (messengerStatus != Status.Active) revert IOpUSDCBridgeAdapter_MessagingDisabled();

    // Ensure the nonce has not already been used
    if (userNonces[_signer][_nonce]) revert IOpUSDCBridgeAdapter_InvalidNonce();

    // Ensure the deadline has not passed
    if (block.timestamp > _deadline) revert IOpUSDCBridgeAdapter_MessageExpired();

    BridgeMessage memory _message =
      BridgeMessage({to: _to, amount: _amount, deadline: _deadline, nonce: _nonce, minGasLimit: _minGasLimit});

    _checkSignature(_signer, _hashMessageStruct(_message), _signature);

    // Mark the nonce as used
    userNonces[_signer][_nonce] = true;

    _sendMessage(_signer, _to, _amount, _minGasLimit);
  }

  /**
   * @notice Receive the message from the other chain and mint the bridged representation for the user
   * @dev This function should only be called when receiving a message to mint the bridged representation
   * @dev If the mint fails the funds might be recovered by calling withdrawLockedFunds
   * @param _user The user to mint the bridged representation for
   * @param _spender The address that provided the tokens
   * @param _amount The amount of tokens to mint
   */
  function receiveMessage(address _user, address _spender, uint256 _amount) external override onlyLinkedAdapter {
    if (messengerStatus == Status.Deprecated) {
      uint32 _minGasLimit = 150_000;
      // Return the funds to the spender in case the target on L2 is a contract that can´t handle the funds on L1
      ICrossDomainMessenger(MESSENGER).sendMessage(
        LINKED_ADAPTER, abi.encodeCall(IOpUSDCBridgeAdapter.receiveMessage, (_spender, _spender, _amount)), _minGasLimit
      );

      emit ReplayedFundsSentBackToL1(_spender, _amount);
    } else {
      // Mint the tokens to the user
      try IUSDC(USDC).mint(_user, _amount) {
        emit MessageReceived(_spender, _user, _amount, MESSENGER);
      } catch {
        // If the mint fails, the user could be locked for multiple reasons such as blacklist or usdc being paused
        lockedFundsDetails[_spender][_user] += _amount;
        emit MessageFailed(_spender, _user, _amount, MESSENGER);
      }
    }
  }

  /**
   * @notice Mints the locked funds from the contract in case they get unlocked
   * @dev Returns the funds to the spender through a message to L1 if the contract is deprecated
   * @param _spender The address that provided the tokens
   * @param _user The user to withdraw the funds for
   */
  function withdrawLockedFunds(address _spender, address _user) external override {
    uint256 _amount = lockedFundsDetails[_spender][_user];
    lockedFundsDetails[_spender][_user] = 0;

    if (messengerStatus != Status.Deprecated) {
      // The check for if the user is blacklisted happens in USDC's contract
      IUSDC(USDC).mint(_user, _amount);
      emit LockedFundsWithdrawn(_user, _amount);
    } else {
      uint32 _minGasLimit = 150_000;
      // Send the message to the linked adapter
      ICrossDomainMessenger(MESSENGER).sendMessage(
        LINKED_ADAPTER,
        abi.encodeCall(IL1OpUSDCBridgeAdapter.receiveWithdrawLockedFundsPostMigration, (_spender, _amount)),
        _minGasLimit
      );
      emit LockedFundsSentBackToL1(_spender, _amount);
    }
  }

  /*///////////////////////////////////////////////////////////////
                        BRIDGED USDC FUNCTIONS
  ///////////////////////////////////////////////////////////////*/

  /**
   * @notice Call with abitrary calldata on USDC contract.
   * @dev can't execute the following list of transactions:
   *  • transferOwnership (0xf2fde38b)
   *  • changeAdmin (0x8f283970)
   * @dev UpgradeTo and UpgradeToAndCall go through the fallback admin
   * @param _data The calldata to execute on the USDC contract
   */
  function callUsdcTransaction(bytes calldata _data) external onlyOwner {
    bytes4 _selector = bytes4(_data);
    bool _success;

    if (
      _selector == _TRANSFER_OWNERSHIP_SELECTOR || _selector == _CHANGE_ADMIN_SELECTOR
        || _selector == _UPDATE_MASTER_MINTER_SELECTOR
    ) {
      revert IOpUSDCBridgeAdapter_ForbiddenTransaction();
    } else if (_selector == _UPGRADE_TO_SELECTOR || _selector == _UPGRADE_TO_AND_CALL_SELECTOR) {
      (_success,) = address(FALLBACK_PROXY_ADMIN).call(_data);
    } else {
      (_success,) = USDC.call(_data);
    }

    if (!_success) {
      revert IOpUSDCBridgeAdapter_InvalidTransaction();
    }

    emit USDCFunctionSent(_selector);
  }

  /*///////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
  ///////////////////////////////////////////////////////////////*/
  /**
   * @notice Send the message to the linked adapter
   * @param _from address that originated the message
   * @param _to target address on the destination chain
   * @param _amount amount of tokens to be bridged
   * @param _minGasLimit minimum gas limit for the other chain to execute the message
   */
  function _sendMessage(address _from, address _to, uint256 _amount, uint32 _minGasLimit) internal {
    IUSDC(USDC).safeTransferFrom(_from, address(this), _amount);

    // Burn the tokens
    IUSDC(USDC).burn(_amount);

    // Send the message to the linked adapter
    ICrossDomainMessenger(MESSENGER).sendMessage(
      LINKED_ADAPTER, abi.encodeCall(IOpUSDCBridgeAdapter.receiveMessage, (_to, _from, _amount)), _minGasLimit
    );

    emit MessageSent(_from, _to, _amount, MESSENGER, _minGasLimit);
  }
}
