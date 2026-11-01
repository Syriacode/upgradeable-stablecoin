// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StableCoin} from "../../src/StableCoin.sol";

/// @notice The invariant fuzzer calls these functions in random order with random arguments.
///         Every input is bounded to a valid range so calls don't revert. A reverted call tests nothing.
contract Handler is Test {
    StableCoin public immutable coin;
    address public immutable minter;
    address[3] public actors;

    // Ghost variables: what the supply SHOULD be, tracked independently of the contract.
    uint256 public ghostMinted;
    uint256 public ghostBurned;

    constructor(StableCoin coin_, address minter_, address[3] memory actors_) {
        coin = coin_;
        minter = minter_;
        actors = actors_;
    }

    function mint(uint256 actorIndex, uint256 amount) external {
        address to = _actor(actorIndex);
        amount = bound(amount, 0, coin.minterAllowance(minter));

        vm.prank(minter);
        coin.mint(to, amount);

        ghostMinted += amount;
    }

    function transfer(uint256 fromIndex, uint256 toIndex, uint256 amount) external {
        address from = _actor(fromIndex);
        address to = _actor(toIndex);
        amount = bound(amount, 0, coin.balanceOf(from));

        vm.prank(from);
        coin.transfer(to, amount);
    }

    /// @dev USDC-style redemption: the holder sends tokens to the minter, and the minter burns them.
    function burn(uint256 actorIndex, uint256 amount) external {
        address holder = _actor(actorIndex);
        amount = bound(amount, 0, coin.balanceOf(holder));

        vm.prank(holder);
        coin.transfer(minter, amount);

        vm.prank(minter);
        coin.burn(amount);

        ghostBurned += amount;
    }

    /// @notice Every address the handler ever moves tokens to.
    function sumBalances() external view returns (uint256 sum) {
        for (uint256 i = 0; i < actors.length; i++) {
            sum += coin.balanceOf(actors[i]);
        }
        sum += coin.balanceOf(minter);
    }

    function _actor(uint256 index) private view returns (address) {
        return actors[index % actors.length];
    }
}
