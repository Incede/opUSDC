// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {OpEURCBridgeAdapter} from 'contracts/universal/OpEURCBridgeAdapter.sol';
import {IL1OpEURCBridgeAdapter} from 'interfaces/IL1OpEURCBridgeAdapter.sol';
import {IL2OpEURCBridgeAdapter} from 'interfaces/IL2OpEURCBridgeAdapter.sol';
import {IOpEURCBridgeAdapter} from 'interfaces/IOpEURCBridgeAdapter.sol';
import {ICrossDomainMessenger} from 'interfaces/external/ICrossDomainMessenger.sol';
import {IEURC} from 'interfaces/external/IEURC.sol';

/**
 * @title L1OpEURCBridgeAdapter
 * @notice L1OpEURCBridgeAdapter is a contract that bridges Bridged EURC from L1 to L2 and and receives it from L2.
 * It is also in charge of pausing and resuming messaging between the L1 and L2 adapters, and properly initiating the
 * migration process to the for bridged EURC to native.
 */
contract L1OpEURCBridgeAdapter is IL1OpEURCBridgeAdapter, OpEURCBridgeAdapter {
  using SafeERC20 for IEURC;

  /// @inheritdoc IL1OpEURCBridgeAdapter
  uint256 public burnAmount;

  /// @inheritdoc IL1OpEURCBridgeAdapter
  address public burnCaller;

  /// @notice Reserve 50 more storage slots to be safe on future upgrades
  uint256[50] private __gap;

  /**
   * @notice Construct the OpEURCBridgeAdapter contract
   * @param _eurc The address of the EURC Contract to be used by the adapter
   * @param _messenger The address of the L1 messenger
   * @param _linkedAdapter The address of the linked adapter
   * @dev The constructor is only used to initialize the OpEURCBridgeAdapter immutable variables
   */
  constructor(
    address _eurc,
    address _messenger,
    address _linkedAdapter
  ) OpEURCBridgeAdapter(_eurc, _messenger, _linkedAdapter) {}

  /**
   * @notice Sets the owner of the contract
   * @param _owner The address of the owner
   * @dev This function needs only used during the deployment of the proxy contract, and it is disabled for the
   * implementation contract
   */
  function initialize(address _owner) external virtual override initializer {
    __Ownable_init(_owner);
    string memory _name = 'OpEURCBridgeAdapter';
    string memory _version = '1.0.0';
    __EIP712_init(_name, _version);
  }

  /*///////////////////////////////////////////////////////////////
                              MIGRATION
  ///////////////////////////////////////////////////////////////*/

  /**
   * @notice Initiates the process to migrate the bridged EURC to native EURC
   * @param _roleCaller The address that will be allowed to transfer the eurc roles
   * @param _burnCaller The address that will be allowed to call this contract to burn the EURC tokens
   * @param _minGasLimitReceiveOnL2 Minimum gas limit that the message can be executed with on L2
   * @param _minGasLimitSetBurnAmount Minimum gas limit that the message can be executed with to set the burn amount
   * @dev Migrating to native is irreversible and will deprecate these adapters
   */
  function migrateToNative(
    address _roleCaller,
    address _burnCaller,
    uint32 _minGasLimitReceiveOnL2,
    uint32 _minGasLimitSetBurnAmount
  ) external onlyOwner {
    // Leave this flow open to resend upgrading flow in case message fails on L2
    // Circle's EURC implementation of `transferOwnership` reverts on address(0)
    if (_roleCaller == address(0) || _burnCaller == address(0)) revert IOpEURCBridgeAdapter_InvalidAddress();

    // Ensure messaging is enabled
    if (messengerStatus != Status.Active && messengerStatus != Status.Upgrading) {
      revert IOpEURCBridgeAdapter_MessagingDisabled();
    }

    burnCaller = _burnCaller;
    messengerStatus = Status.Upgrading;

    ICrossDomainMessenger(MESSENGER).sendMessage(
      LINKED_ADAPTER,
      abi.encodeCall(IL2OpEURCBridgeAdapter.receiveMigrateToNative, (_roleCaller, _minGasLimitSetBurnAmount)),
      _minGasLimitReceiveOnL2
    );

    emit MigratingToNative(MESSENGER, _burnCaller);
  }

  /**
   * @notice Sets the amount of EURC tokens that will be burned when the burnLockedEURC function is called
   * @param _amount The amount of EURC tokens that will be burned
   * @dev Only callable by a whitelisted messenger during its migration process
   */
  function setBurnAmount(uint256 _amount) external onlyLinkedAdapter {
    if (messengerStatus != Status.Upgrading) revert IOpEURCBridgeAdapter_NotUpgrading();

    burnAmount = _amount;
    messengerStatus = Status.Deprecated;

    emit BurnAmountSet(_amount);
  }

  /**
   * @notice Burns the EURC tokens locked in the contract
   * @dev The amount is determined by the burnAmount variable, which is set in the setBurnAmount function
   */
  function burnLockedEURC() external {
    if (msg.sender != burnCaller) revert IOpEURCBridgeAdapter_InvalidSender();

    // If the adapter is not deprecated the burn amount has not been set
    if (messengerStatus != Status.Deprecated) revert IOpEURCBridgeAdapter_BurnAmountNotSet();

    // NOTE: This is a very edge case and will only happen if the chain operator adds a second minter on L2
    // So now this adapter doesnt have the full backing supply locked in this contract
    // in case the bridged eurc token has other minters and the supply sent is greater then what we have
    // We need to burn the full amount stored in this contract
    // This could also cause in-flight messages to fail because of the multiple supply sources
    uint256 _burnAmount = burnAmount;
    uint256 _balanceOf = IEURC(EURC).balanceOf(address(this));
    _burnAmount = _burnAmount > _balanceOf ? _balanceOf : _burnAmount;

    // Burn the EURC tokens
    if (_burnAmount != 0) {
      IEURC(EURC).burn(_burnAmount);
    }

    // Set the burn amount to 0
    burnAmount = 0;
    burnCaller = address(0);
    emit MigrationComplete(_burnAmount);
  }

  /*///////////////////////////////////////////////////////////////
                          ADMIN CONTROL
  ///////////////////////////////////////////////////////////////*/

  /**
   * @notice Send a message to the linked adapter to call receiveStopMessaging() and stop outgoing messages.
   * @dev Only callable by the owner of the adapter
   * @param _minGasLimit Minimum gas limit that the message can be executed with
   */
  function stopMessaging(uint32 _minGasLimit) external onlyOwner {
    // Ensure messaging is enabled
    // If its paused we still leave this function open to be called in case the message fails on L2
    if (messengerStatus != Status.Active && messengerStatus != Status.Paused) {
      revert IOpEURCBridgeAdapter_MessagingDisabled();
    }

    messengerStatus = Status.Paused;

    ICrossDomainMessenger(MESSENGER).sendMessage(
      LINKED_ADAPTER, abi.encodeCall(IL2OpEURCBridgeAdapter.receiveStopMessaging, ()), _minGasLimit
    );

    emit MessagingStopped(MESSENGER);
  }

  /**
   * @notice Resume messaging on the messenger
   * @dev Only callable by the owner
   * @dev Can't resume deprecated or upgrading messengers
   * @param _minGasLimit Minimum gas limit that the message can be executed with
   */
  function resumeMessaging(uint32 _minGasLimit) external onlyOwner {
    // Ensure messaging is disabled
    // If its active we still leave this function open to be called in case the message fails on L2
    if (messengerStatus != Status.Paused && messengerStatus != Status.Active) {
      revert IOpEURCBridgeAdapter_MessagingEnabled();
    }

    messengerStatus = Status.Active;

    ICrossDomainMessenger(MESSENGER).sendMessage(
      LINKED_ADAPTER, abi.encodeCall(IL2OpEURCBridgeAdapter.receiveResumeMessaging, ()), _minGasLimit
    );

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
    if (_to == address(0)) revert IOpEURCBridgeAdapter_InvalidAddress();

    // Ensure the address is not blacklisted
    if (IEURC(EURC).isBlacklisted(_to)) revert IOpEURCBridgeAdapter_BlacklistedAddress();

    // Ensure messaging is enabled
    if (messengerStatus != Status.Active) revert IOpEURCBridgeAdapter_MessagingDisabled();

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
    if (_to == address(0)) revert IOpEURCBridgeAdapter_InvalidAddress();

    // Ensure the address is not blacklisted
    if (IEURC(EURC).isBlacklisted(_to)) revert IOpEURCBridgeAdapter_BlacklistedAddress();

    // Ensure messaging is enabled
    if (messengerStatus != Status.Active) revert IOpEURCBridgeAdapter_MessagingDisabled();

    // Ensure the nonce has not already been used
    if (userNonces[_signer][_nonce]) revert IOpEURCBridgeAdapter_InvalidNonce();

    // Ensure the deadline has not passed
    if (block.timestamp > _deadline) revert IOpEURCBridgeAdapter_MessageExpired();

    BridgeMessage memory _message =
      BridgeMessage({to: _to, amount: _amount, deadline: _deadline, nonce: _nonce, minGasLimit: _minGasLimit});

    _checkSignature(_signer, _hashMessageStruct(_message), _signature);

    // Mark the nonce as used
    userNonces[_signer][_nonce] = true;

    _sendMessage(_signer, _to, _amount, _minGasLimit);
  }

  /**
   * @notice Receive the message from the other chain and transfer tokens to the user
   * @dev This function should only be called when receiving a message to transfer tokens
   * @dev If the transfer fails the funds might be recovered by calling withdrawLockedFunds
   * @param _user The user to transfer the tokens to
   * @param _spender The address that provided the tokens
   * @param _amount The amount of tokens to transfer
   */
  function receiveMessage(address _user, address _spender, uint256 _amount) external override onlyLinkedAdapter {
    // Transfer the tokens to the user
    try this.attemptTransfer(_user, _amount) {
      emit MessageReceived(_spender, _user, _amount, MESSENGER);
    } catch {
      // If the transfer fails, the user could be locked for multiple reasons such as blacklist or eurc being paused
      lockedFundsDetails[_spender][_user] += _amount;
      emit MessageFailed(_spender, _user, _amount, MESSENGER);
    }
  }

  /**
   * @notice Receives a message from L2 if the adapter is deprecated and a user is withdrawing locked funds
   * @dev If the _spender is still locked, the user will be forced to replay this message
   * @param _spender The user that initially provided the tokens
   * @param _amount The amount of tokens to withdraw
   */
  function receiveWithdrawLockedFundsPostMigration(address _spender, uint256 _amount) external onlyLinkedAdapter {
    if (messengerStatus != Status.Deprecated) revert IOpEURCBridgeAdapter_NotMigrated();

    // If the spender is still locked, the user will be forced to replay this message
    IEURC(EURC).safeTransfer(_spender, _amount);

    emit LockedFundsWithdrawn(_spender, _amount);
  }

  /**
   * @notice Withdraws the locked funds from the contract in case they get unlocked
   * @param _spender The address that provided the tokens
   * @param _user The user to withdraw the funds for
   */
  function withdrawLockedFunds(address _spender, address _user) external override {
    uint256 _amount = lockedFundsDetails[_spender][_user];
    lockedFundsDetails[_spender][_user] = 0;

    // The check for if the user is locked happens in EURC's contract
    IEURC(EURC).safeTransfer(_user, _amount);

    emit LockedFundsWithdrawn(_user, _amount);
  }

  /**
   * @notice Attempts to transfer the tokens to the user
   * @param _to The target address on the destination chain
   * @param _amount The amount of tokens to send
   * @dev This function should only be called when receiving a message
   * And is a workaround for the fact that try/catch
   * Only works on external calls and SafeERC20 is an internal library
   */
  function attemptTransfer(address _to, uint256 _amount) external {
    if (msg.sender != address(this)) revert IOpEURCBridgeAdapter_InvalidSender();
    IEURC(EURC).safeTransfer(_to, _amount);
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
    // Transfer the tokens to the contract
    IEURC(EURC).safeTransferFrom(_from, address(this), _amount);

    // Send the message to the linked adapter
    ICrossDomainMessenger(MESSENGER).sendMessage(
      LINKED_ADAPTER, abi.encodeCall(IOpEURCBridgeAdapter.receiveMessage, (_to, _from, _amount)), _minGasLimit
    );

    emit MessageSent(_from, _to, _amount, MESSENGER, _minGasLimit);
  }
}
