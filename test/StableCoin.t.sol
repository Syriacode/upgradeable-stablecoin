// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StableCoin} from "../src/StableCoin.sol";
import {BaseTest} from "./Base.t.sol";

contract StableCoinTest is BaseTest {
    // --- step 2: deployment & initialization -------------------------------

    function test_Metadata() public view {
        assertEq(coin.name(), NAME);
        assertEq(coin.symbol(), SYMBOL);
        assertEq(coin.decimals(), 6);
    }

    function test_AdminHasAdminRole() public view {
        assertTrue(coin.hasRole(coin.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_RevertWhen_InitializeCalledTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        coin.initialize(NAME, SYMBOL, alice);
    }

    function test_RevertWhen_InitializeWithZeroAdmin() public {
        StableCoin impl = new StableCoin();
        bytes memory initData = abi.encodeCall(StableCoin.initialize, (NAME, SYMBOL, address(0)));

        vm.expectRevert(StableCoin.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    // --- step 3: roles, minter allowances, mint & burn ---------------------

    function test_MintReducesAllowance() public {
        uint256 amount = 250 * ONE_DOLLAR;

        vm.prank(minter);
        coin.mint(alice, amount);

        assertEq(coin.balanceOf(alice), amount);
        assertEq(coin.totalSupply(), amount);
        assertEq(coin.minterAllowance(minter), MINTER_ALLOWANCE - amount);
    }

    function test_RevertWhen_MintExceedsAllowance() public {
        uint256 amount = MINTER_ALLOWANCE + 1;

        vm.expectRevert(abi.encodeWithSelector(StableCoin.ExceedsMinterAllowance.selector, amount, MINTER_ALLOWANCE));
        vm.prank(minter);
        coin.mint(alice, amount);
    }

    function test_RevertWhen_NonMinterMints() public {
        // Read the role BEFORE vm.prank: the getter is itself a call and would consume the prank.
        bytes32 minterRole = coin.MINTER_ROLE();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, minterRole)
        );
        vm.prank(alice);
        coin.mint(alice, 1);
    }

    function test_BurnReducesTotalSupply() public {
        uint256 minted = 100 * ONE_DOLLAR;
        uint256 burned = 40 * ONE_DOLLAR;

        vm.startPrank(minter);
        coin.mint(minter, minted);
        coin.burn(burned);
        vm.stopPrank();

        assertEq(coin.totalSupply(), minted - burned);
        assertEq(coin.balanceOf(minter), minted - burned);
    }

    function testFuzz_MintThenBurn(uint256 amount) public {
        amount = bound(amount, 1, MINTER_ALLOWANCE);

        vm.startPrank(minter);
        coin.mint(minter, amount);
        coin.burn(amount);
        vm.stopPrank();

        assertEq(coin.totalSupply(), 0);
        assertEq(coin.balanceOf(minter), 0);
        assertEq(coin.minterAllowance(minter), MINTER_ALLOWANCE - amount); // burning doesn't refund allowance
    }

    function test_RevertWhen_NonAdminSetsAllowance() public {
        bytes32 adminRole = coin.DEFAULT_ADMIN_ROLE();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, minter, adminRole)
        );
        vm.prank(minter);
        coin.setMinterAllowance(minter, type(uint256).max);
    }

    // --- step 4: pause & blocklist ------------------------------------------

    function _mintToAlice(uint256 amount) internal {
        vm.prank(minter);
        coin.mint(alice, amount);
    }

    function _blocklist(address account) internal {
        vm.prank(blocklister);
        coin.setBlocklisted(account, true);
    }

    function test_RevertWhen_TransferWhilePaused() public {
        _mintToAlice(100 * ONE_DOLLAR);

        vm.prank(pauser);
        coin.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(alice);
        coin.transfer(bob, 10 * ONE_DOLLAR);
    }

    function test_UnpauseRestoresTransfers() public {
        _mintToAlice(100 * ONE_DOLLAR);

        vm.startPrank(pauser);
        coin.pause();
        coin.unpause();
        vm.stopPrank();

        vm.prank(alice);
        coin.transfer(bob, 10 * ONE_DOLLAR);

        assertEq(coin.balanceOf(bob), 10 * ONE_DOLLAR);
        assertEq(coin.balanceOf(alice), 90 * ONE_DOLLAR);
    }

    function test_RevertWhen_BlocklistedSenderTransfers() public {
        _mintToAlice(100 * ONE_DOLLAR);
        _blocklist(alice);

        vm.expectRevert(abi.encodeWithSelector(StableCoin.AccountBlocklisted.selector, alice));
        vm.prank(alice);
        coin.transfer(bob, 10 * ONE_DOLLAR);
    }

    function test_RevertWhen_BlocklistedRecipientReceives() public {
        _mintToAlice(100 * ONE_DOLLAR);
        _blocklist(bob);

        vm.expectRevert(abi.encodeWithSelector(StableCoin.AccountBlocklisted.selector, bob));
        vm.prank(alice);
        coin.transfer(bob, 10 * ONE_DOLLAR);
    }

    function test_RevertWhen_BlocklistedSpenderUsesTransferFrom() public {
        address spender = makeAddr("spender");
        _mintToAlice(100 * ONE_DOLLAR);

        vm.prank(alice);
        coin.approve(spender, 50 * ONE_DOLLAR);
        _blocklist(spender);

        // from (alice) and to (bob) are both clean; only the msg.sender check catches this.
        vm.expectRevert(abi.encodeWithSelector(StableCoin.AccountBlocklisted.selector, spender));
        vm.prank(spender);
        coin.transferFrom(alice, bob, 50 * ONE_DOLLAR);
    }

    function test_RevertWhen_MintToBlocklisted() public {
        _blocklist(alice);

        vm.expectRevert(abi.encodeWithSelector(StableCoin.AccountBlocklisted.selector, alice));
        vm.prank(minter);
        coin.mint(alice, 1);
    }
}
