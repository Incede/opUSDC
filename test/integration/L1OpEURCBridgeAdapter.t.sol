// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IntegrationBase} from './IntegrationBase.sol';
import {IOpEURCBridgeAdapter} from 'interfaces/IOpEURCBridgeAdapter.sol';

contract Integration_Bridging is IntegrationBase {
  string internal constant _NAME = 'OpEURCBridgeAdapter';
  string internal constant _VERSION = '1.0.0';

  /**
   * @notice Test the bridging process from L1 -> L2
   */
  function test_bridgeFromL1() public {
    vm.selectFork(mainnet);

    // We need to do this instead of `deal` because deal doesnt change `totalSupply` state
    vm.prank(MAINNET_EURC.masterMinter());
    MAINNET_EURC.mint(_user, _amount);

    vm.startPrank(_user);
    MAINNET_EURC.approve(address(l1Adapter), _amount);
    l1Adapter.sendMessage(_user, _amount, _MIN_GAS_LIMIT);
    vm.stopPrank();

    assertEq(MAINNET_EURC.balanceOf(_user), 0);
    assertEq(MAINNET_EURC.balanceOf(address(l1Adapter)), _amount);

    vm.selectFork(optimism);
    uint256 _userBalanceBefore = bridgedEURC.balanceOf(_user);

    _relayL1ToL2Message(
      OP_ALIASED_L1_MESSENGER,
      address(l1Adapter),
      address(l2Adapter),
      _ZERO_VALUE,
      1_000_000,
      abi.encodeWithSignature('receiveMessage(address,address,uint256)', _user, _user, _amount)
    );

    assertEq(bridgedEURC.balanceOf(_user), _userBalanceBefore + _amount);
  }

  /**
   * @notice Test the bridging process from L1 -> L2 with a different target
   */
  function test_bridgeFromL1DifferentTarget() public {
    vm.selectFork(mainnet);

    address _l2Target = makeAddr('l2Target');

    // We need to do this instead of `deal` because deal doesnt change `totalSupply` state
    vm.prank(MAINNET_EURC.masterMinter());
    MAINNET_EURC.mint(_user, _amount);

    vm.startPrank(_user);
    MAINNET_EURC.approve(address(l1Adapter), _amount);
    l1Adapter.sendMessage(_l2Target, _amount, _MIN_GAS_LIMIT);
    vm.stopPrank();

    assertEq(MAINNET_EURC.balanceOf(_user), 0);
    assertEq(MAINNET_EURC.balanceOf(address(l1Adapter)), _amount);

    vm.selectFork(optimism);
    uint256 _userBalanceBefore = bridgedEURC.balanceOf(_user);
    _relayL1ToL2Message(
      OP_ALIASED_L1_MESSENGER,
      address(l1Adapter),
      address(l2Adapter),
      _ZERO_VALUE,
      1_000_000,
      abi.encodeWithSignature('receiveMessage(address,address,uint256)', _l2Target, _user, _amount)
    );

    assertEq(bridgedEURC.balanceOf(_l2Target), _userBalanceBefore + _amount);
    assertEq(bridgedEURC.balanceOf(_user), 0);
  }

  /**
   * @notice Test bridging with signature
   */
  function test_bridgeFromL1WithSig() public {
    (address _signerAd, uint256 _signerPk) = makeAddrAndKey('signer');
    vm.selectFork(mainnet);

    // We need to do this instead of `deal` because deal doesnt change `totalSupply` state
    vm.startPrank(MAINNET_EURC.masterMinter());
    MAINNET_EURC.mint(_signerAd, _amount);
    // Minting for user to check its not spent when they execute
    // We need to do this instead of `deal` because deal doesnt change `totalSupply` state
    MAINNET_EURC.mint(_user, _amount);
    vm.stopPrank();

    vm.prank(_signerAd);
    MAINNET_EURC.approve(address(l1Adapter), _amount);
    uint256 _deadline = block.timestamp + 1 days;
    bytes memory _signature = _generateSignature(
      _NAME,
      _VERSION,
      _signerAd,
      _amount,
      _deadline,
      _MIN_GAS_LIMIT,
      _USER_NONCE,
      _signerAd,
      _signerPk,
      address(l1Adapter)
    );

    // Different address can execute the message
    vm.prank(_user);
    l1Adapter.sendMessage(_signerAd, _signerAd, _amount, _signature, _USER_NONCE, _deadline, _MIN_GAS_LIMIT);

    assertEq(MAINNET_EURC.balanceOf(_signerAd), 0);
    assertEq(MAINNET_EURC.balanceOf(_user), _amount);
    assertEq(MAINNET_EURC.balanceOf(address(l1Adapter)), _amount);

    vm.selectFork(optimism);
    uint256 _userBalanceBefore = bridgedEURC.balanceOf(_user);
    _relayL1ToL2Message(
      OP_ALIASED_L1_MESSENGER,
      address(l1Adapter),
      address(l2Adapter),
      _ZERO_VALUE,
      1_000_000,
      abi.encodeWithSignature('receiveMessage(address,address,uint256)', _signerAd, _signerAd, _amount)
    );

    assertEq(bridgedEURC.balanceOf(_signerAd), _userBalanceBefore + _amount);
    assertEq(bridgedEURC.balanceOf(_user), 0);
  }

  /**
   * @notice Test signature message reverts with a signature that was canceled by disabling the nonce
   */
  function test_bridgeFromL1WithCanceledSignature() public {
    (address _signerAd, uint256 _signerPk) = makeAddrAndKey('signer');
    vm.selectFork(mainnet);

    // We need to do this instead of `deal` because deal doesnt change `totalSupply` state
    vm.prank(MAINNET_EURC.masterMinter());
    MAINNET_EURC.mint(_signerAd, _amount);

    // Give allowance to the adapter
    vm.prank(_signerAd);
    MAINNET_EURC.approve(address(l1Adapter), _amount);

    // Changing to `to` param to _user but we call it with _signerAd
    uint256 _deadline = block.timestamp + 1 days;
    bytes memory _signature = _generateSignature(
      _NAME, _VERSION, _user, _amount, _deadline, _MIN_GAS_LIMIT, _USER_NONCE, _signerAd, _signerPk, address(l1Adapter)
    );

    // Cancel the signature
    vm.prank(_signerAd);
    l1Adapter.cancelSignature(_USER_NONCE);

    // Different address will execute the message, and it should revert because the nonce is disabled
    vm.startPrank(_user);
    vm.expectRevert(IOpEURCBridgeAdapter.IOpEURCBridgeAdapter_InvalidNonce.selector);
    l1Adapter.sendMessage(_signerAd, _signerAd, _amount, _signature, _USER_NONCE, _deadline, _MIN_GAS_LIMIT);
  }

  /**
   * @notice Test signature message reverts with incorrect signature
   */
  function test_bridgeFromL1WithIncorrectSignature() public {
    vm.selectFork(mainnet);
    (address _signerAd, uint256 _signerPk) = makeAddrAndKey('signer');

    // We need to do this instead of `deal` because deal doesnt change `totalSupply` state
    vm.prank(MAINNET_EURC.masterMinter());
    MAINNET_EURC.mint(_signerAd, _amount);

    // Give allowance to the adapter
    vm.prank(_signerAd);
    MAINNET_EURC.approve(address(l1Adapter), _amount);

    // Changing to `to` param to _user but we call it with _signerAd
    uint256 _deadline = block.timestamp + 1 days;
    bytes memory _signature = _generateSignature(
      _NAME, _VERSION, _user, _amount, _deadline, _MIN_GAS_LIMIT, _USER_NONCE, _signerAd, _signerPk, address(l1Adapter)
    );

    // Different address can execute the message
    vm.startPrank(_user);
    ///  NOTE: Didn't us `vm.expectRevert(IOpEURCBridgeAdapter.IOpEURCBridgeAdapter_InvalidSignature.selector)` because
    /// it reverts with that error, but then the test fails because of a foundry issue with the error message
    /// `contract signer does not exist`, which is not true.
    vm.expectRevert();
    l1Adapter.sendMessage(_signerAd, _signerAd, _amount, _signature, _USER_NONCE, _deadline, _MIN_GAS_LIMIT);

    vm.stopPrank();
  }

  function test_recoverBlacklistedFundsAfterMigration() public {
    // Blacklist `_user` on L2
    vm.selectFork(optimism);
    vm.prank(bridgedEURC.blacklister());
    bridgedEURC.blacklist(_user);

    // Create address for the spender
    address _spender = makeAddr('spender');

    // Select mainnet fork
    vm.selectFork(mainnet);

    // Mint mainnet EURC to the spender
    vm.prank(MAINNET_EURC.masterMinter());
    MAINNET_EURC.mint(_spender, _amount);

    // Approve the L1 adapter to spend the EURC
    vm.prank(_spender);
    MAINNET_EURC.approve(address(l1Adapter), _amount);

    // Spender send EURC to the User on L2
    vm.prank(_spender);
    l1Adapter.sendMessage(_user, _amount, _MIN_GAS_LIMIT);

    // Check that the EURC are correctly sent to the user
    assertEq(MAINNET_EURC.balanceOf(_spender), 0);

    // Relay the message to L2
    vm.selectFork(optimism);
    _relayL1ToL2Message(
      OP_ALIASED_L1_MESSENGER,
      address(l1Adapter),
      address(l2Adapter),
      _ZERO_VALUE,
      1_000_000,
      abi.encodeWithSignature('receiveMessage(address,address,uint256)', _user, _spender, _amount)
    );

    // Check that the locked funds are correctly computed
    assertEq(l2Adapter.lockedFundsDetails(_spender, _user), _amount);

    // Migration to native EURC
    {
      address _roleCaller = makeAddr('circle');
      address _burnCaller = makeAddr('circle');
      uint32 _minGasLimitReceiveOnL2 = 1_000_000;
      uint32 _minGasLimitSetBurnAmount = 1_000_000;

      vm.selectFork(mainnet);
      vm.prank(_owner);
      l1Adapter.migrateToNative(_roleCaller, _burnCaller, _MIN_GAS_LIMIT, _MIN_GAS_LIMIT);

      //This is necessary to set the messenger status to deprecated on L1
      vm.selectFork(optimism);
      _relayL1ToL2Message(
        OP_ALIASED_L1_MESSENGER,
        address(l1Adapter),
        address(l2Adapter),
        _ZERO_VALUE,
        _minGasLimitReceiveOnL2,
        abi.encodeWithSignature('receiveMigrateToNative(address,uint32)', _roleCaller, _minGasLimitSetBurnAmount)
      );

      assertEq(uint256(l2Adapter.messengerStatus()), uint256(IOpEURCBridgeAdapter.Status.Deprecated));

      uint256 _burnAmount = bridgedEURC.totalSupply();

      //This is necessary to set the messenger status to deprecated on L1
      vm.selectFork(mainnet);
      _relayL2ToL1Message(
        address(l2Adapter),
        address(l1Adapter),
        _ZERO_VALUE,
        _minGasLimitSetBurnAmount,
        abi.encodeWithSignature('setBurnAmount(uint256)', _burnAmount)
      );

      assertEq(uint256(l1Adapter.messengerStatus()), uint256(IOpEURCBridgeAdapter.Status.Deprecated));
    }

    // Check that any user can call the withdrawLockedFunds function
    address _anyUser = makeAddr('anyUser');
    vm.selectFork(optimism);
    vm.prank(_anyUser);
    l2Adapter.withdrawLockedFunds(_spender, _user);

    // Check that the blacklisted funds are correctly removed
    assertEq(l2Adapter.lockedFundsDetails(_spender, _user), 0);

    // Check that funds are returned to the spender if is not blacklisted
    vm.selectFork(mainnet);
    assertEq(MAINNET_EURC.isBlacklisted(_spender), false);
    _relayL2ToL1Message(
      address(l2Adapter),
      address(l1Adapter),
      _ZERO_VALUE,
      _MIN_GAS_LIMIT,
      abi.encodeWithSignature('receiveWithdrawLockedFundsPostMigration(address,uint256)', _spender, _amount)
    );

    // Check that the funds are correctly returned to the spender
    assertEq(MAINNET_EURC.balanceOf(_spender), _amount);
  }
}

contract Integration_Migration is IntegrationBase {
  address internal _circle = makeAddr('circle');
  uint32 internal _minGasLimitReceiveOnL2 = 1_000_000;
  uint32 internal _minGasLimitSetBurnAmount = 1_000_000;

  function setUp() public override {
    super.setUp();

    vm.selectFork(mainnet);
    // Adapter needs to be minter to burn
    vm.prank(MAINNET_EURC.masterMinter());
    MAINNET_EURC.configureMinter(address(l1Adapter), 0);
  }

  /**
   * @notice Test the migration to native eurc flow
   */
  function test_migrationToNativeEURC() public {
    _mintSupplyOnL2(optimism, OP_ALIASED_L1_MESSENGER, _amount);

    vm.selectFork(mainnet);

    vm.prank(_owner);
    l1Adapter.migrateToNative(_circle, _circle, _minGasLimitReceiveOnL2, _minGasLimitSetBurnAmount);

    assertEq(uint256(l1Adapter.messengerStatus()), uint256(IOpEURCBridgeAdapter.Status.Upgrading));
    assertEq(l1Adapter.burnCaller(), _circle);

    vm.selectFork(optimism);
    _relayL1ToL2Message(
      OP_ALIASED_L1_MESSENGER,
      address(l1Adapter),
      address(l2Adapter),
      _ZERO_VALUE,
      _minGasLimitReceiveOnL2,
      abi.encodeWithSignature('receiveMigrateToNative(address,uint32)', _circle, _minGasLimitSetBurnAmount)
    );

    uint256 _burnAmount = bridgedEURC.totalSupply();

    assertEq(uint256(l2Adapter.messengerStatus()), uint256(IOpEURCBridgeAdapter.Status.Deprecated));
    assertEq(l2Adapter.roleCaller(), _circle);
    assertEq(bridgedEURC.isMinter(address(l2Adapter)), false);

    vm.prank(_circle);
    l2Adapter.transferEURCRoles(_circle);

    assertEq(bridgedEURC.owner(), _circle);

    vm.selectFork(mainnet);
    _relayL2ToL1Message(
      address(l2Adapter),
      address(l1Adapter),
      _ZERO_VALUE,
      _minGasLimitSetBurnAmount,
      abi.encodeWithSignature('setBurnAmount(uint256)', _burnAmount)
    );

    assertEq(l1Adapter.burnAmount(), _burnAmount);
    assertEq(l1Adapter.EURC(), address(MAINNET_EURC));
    assertEq(uint256(l1Adapter.messengerStatus()), uint256(IOpEURCBridgeAdapter.Status.Deprecated));

    vm.prank(_circle);
    l1Adapter.burnLockedEURC();

    assertEq(MAINNET_EURC.balanceOf(address(l1Adapter)), 0);
    assertEq(l1Adapter.burnAmount(), 0);
    assertEq(l1Adapter.burnCaller(), address(0));
  }

  /**
   * @notice Test the migration to native eurc flow with zero balance on L1
   * @dev This is a very edge case and will only happen if the chain operator adds a second minter on L2
   *      So now this adapter doesnt have the full backing supply locked in this contract
   */
  function test_migrationToNativeEURCWithZeroBalanceOnL1() public {
    vm.selectFork(optimism);
    vm.prank(bridgedEURC.masterMinter());
    bridgedEURC.configureMinter(_owner, type(uint256).max);
    vm.prank(_owner);
    bridgedEURC.mint(_owner, _amount);

    vm.selectFork(mainnet);

    vm.prank(_owner);
    l1Adapter.migrateToNative(_circle, _circle, _minGasLimitReceiveOnL2, _minGasLimitSetBurnAmount);

    assertEq(uint256(l1Adapter.messengerStatus()), uint256(IOpEURCBridgeAdapter.Status.Upgrading));
    assertEq(l1Adapter.burnCaller(), _circle);

    vm.selectFork(optimism);
    _relayL1ToL2Message(
      OP_ALIASED_L1_MESSENGER,
      address(l1Adapter),
      address(l2Adapter),
      _ZERO_VALUE,
      _minGasLimitReceiveOnL2,
      abi.encodeWithSignature('receiveMigrateToNative(address,uint32)', _circle, _minGasLimitSetBurnAmount)
    );

    uint256 _burnAmount = bridgedEURC.totalSupply();

    assertEq(uint256(l2Adapter.messengerStatus()), uint256(IOpEURCBridgeAdapter.Status.Deprecated));
    assertEq(l2Adapter.roleCaller(), _circle);
    assertEq(bridgedEURC.isMinter(address(l2Adapter)), false);

    vm.prank(_circle);
    l2Adapter.transferEURCRoles(_circle);

    assertEq(bridgedEURC.owner(), _circle);

    vm.selectFork(mainnet);
    _relayL2ToL1Message(
      address(l2Adapter),
      address(l1Adapter),
      _ZERO_VALUE,
      _minGasLimitSetBurnAmount,
      abi.encodeWithSignature('setBurnAmount(uint256)', _burnAmount)
    );

    assertEq(l1Adapter.burnAmount(), _burnAmount);
    assertEq(l1Adapter.EURC(), address(MAINNET_EURC));
    assertEq(uint256(l1Adapter.messengerStatus()), uint256(IOpEURCBridgeAdapter.Status.Deprecated));

    vm.prank(_circle);
    l1Adapter.burnLockedEURC();

    assertEq(MAINNET_EURC.balanceOf(address(l1Adapter)), 0);
    assertEq(l1Adapter.burnAmount(), 0);
    assertEq(l1Adapter.burnCaller(), address(0));
  }

  /**
   * @notice Test relay message after migration to native eurc
   */
  function test_relayMessageAfterMigrationToNativeEURC() public {
    vm.selectFork(mainnet);

    uint256 _supply = 1_000_000;

    vm.startPrank(MAINNET_EURC.masterMinter());
    MAINNET_EURC.configureMinter(MAINNET_EURC.masterMinter(), _supply);
    MAINNET_EURC.mint(_user, _supply);
    vm.stopPrank();

    vm.startPrank(_user);
    MAINNET_EURC.approve(address(l1Adapter), _supply);
    l1Adapter.sendMessage(_user, _supply, _MIN_GAS_LIMIT);
    vm.stopPrank();

    vm.prank(_owner);
    l1Adapter.migrateToNative(_circle, _circle, _minGasLimitReceiveOnL2, _minGasLimitSetBurnAmount);

    vm.selectFork(optimism);
    _relayL1ToL2Message(
      OP_ALIASED_L1_MESSENGER,
      address(l1Adapter),
      address(l2Adapter),
      _ZERO_VALUE,
      _minGasLimitReceiveOnL2,
      abi.encodeWithSignature('receiveMigrateToNative(address,uint32)', _circle, _minGasLimitSetBurnAmount)
    );

    uint256 _burnAmount = bridgedEURC.totalSupply();
    assertEq(uint256(l2Adapter.messengerStatus()), uint256(IOpEURCBridgeAdapter.Status.Deprecated));

    vm.selectFork(mainnet);
    _relayL2ToL1Message(
      address(l2Adapter),
      address(l1Adapter),
      _ZERO_VALUE,
      _minGasLimitSetBurnAmount,
      abi.encodeWithSignature('setBurnAmount(uint256)', _burnAmount)
    );

    assertEq(uint256(l1Adapter.messengerStatus()), uint256(IOpEURCBridgeAdapter.Status.Deprecated));

    vm.selectFork(optimism);

    vm.expectCall(
      0x4200000000000000000000000000000000000007,
      abi.encodeWithSignature(
        'sendMessage(address,bytes,uint32)',
        address(l1Adapter),
        abi.encodeWithSignature('receiveMessage(address,address,uint256)', _user, _user, _amount),
        150_000
      )
    );

    uint256 _totalSupplyBefore = bridgedEURC.totalSupply();

    _relayL1ToL2Message(
      OP_ALIASED_L1_MESSENGER,
      address(l1Adapter),
      address(l2Adapter),
      _ZERO_VALUE,
      1_000_000,
      abi.encodeWithSignature('receiveMessage(address,address,uint256)', _user, _user, _amount)
    );

    assertEq(bridgedEURC.totalSupply(), _totalSupplyBefore);
  }
}

contract Integration_Integration_PermissionedFlows is IntegrationBase {
  /**
   * @notice Test that the messaging is stopped and resumed correctly from L1 on
   * both layers
   */
  function test_stopAndResumeMessaging() public {
    vm.selectFork(mainnet);

    assertEq(uint256(l1Adapter.messengerStatus()), uint256(IOpEURCBridgeAdapter.Status.Active));

    vm.prank(_owner);
    l1Adapter.stopMessaging(_MIN_GAS_LIMIT);

    assertEq(uint256(l1Adapter.messengerStatus()), uint256(IOpEURCBridgeAdapter.Status.Paused));

    vm.selectFork(optimism);
    _relayL1ToL2Message(
      OP_ALIASED_L1_MESSENGER,
      address(l1Adapter),
      address(l2Adapter),
      _ZERO_VALUE,
      _MIN_GAS_LIMIT,
      abi.encodeWithSignature('receiveStopMessaging()')
    );

    assertEq(uint256(l2Adapter.messengerStatus()), uint256(IOpEURCBridgeAdapter.Status.Paused));

    vm.selectFork(mainnet);

    vm.prank(_owner);
    l1Adapter.resumeMessaging(_MIN_GAS_LIMIT);

    assertEq(uint256(l1Adapter.messengerStatus()), uint256(IOpEURCBridgeAdapter.Status.Active));

    vm.selectFork(optimism);

    _relayL1ToL2Message(
      OP_ALIASED_L1_MESSENGER,
      address(l1Adapter),
      address(l2Adapter),
      _ZERO_VALUE,
      _MIN_GAS_LIMIT,
      abi.encodeWithSignature('receiveResumeMessaging()')
    );

    assertEq(uint256(l2Adapter.messengerStatus()), uint256(IOpEURCBridgeAdapter.Status.Active));
  }

  /**
   * @notice Test that the user can withdraw the blacklisted funds if they get unblacklisted
   */
  function test_userCanWithdrawBlacklistedFunds() public {
    vm.selectFork(mainnet);
    _mintSupplyOnL2(optimism, OP_ALIASED_L1_MESSENGER, _amount);

    vm.selectFork(optimism);
    vm.startPrank(_user);
    bridgedEURC.approve(address(l2Adapter), _amount);
    l2Adapter.sendMessage(_user, _amount, _MIN_GAS_LIMIT);
    vm.stopPrank();
    assertEq(bridgedEURC.balanceOf(_user), 0);

    vm.selectFork(mainnet);

    vm.prank(MAINNET_EURC.blacklister());
    MAINNET_EURC.blacklist(_user);
    _relayL2ToL1Message(
      address(l2Adapter),
      address(l1Adapter),
      _ZERO_VALUE,
      _MIN_GAS_LIMIT,
      abi.encodeWithSignature('receiveMessage(address,address,uint256)', _user, _user, _amount)
    );

    assertEq(MAINNET_EURC.balanceOf(_user), 0);

    vm.prank(MAINNET_EURC.blacklister());
    MAINNET_EURC.unBlacklist(_user);

    vm.prank(_user);
    l1Adapter.withdrawLockedFunds(_user, _user);

    assertEq(MAINNET_EURC.balanceOf(_user), _amount);
    assertEq(l1Adapter.lockedFundsDetails(_user, _user), 0);
  }
}
