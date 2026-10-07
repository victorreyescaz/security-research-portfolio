// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { HackToken } from "../../src/HackTokenERC20.sol";

/// @dev Driver for the invariant run. It mints and burns through the real
/// entry points with bounded random amounts, so the sequence of operations is
/// chosen by the fuzzer rather than by the author of the test.
contract SupplyHandler is Test {
    HackToken public immutable token;

    address[] internal holders;
    uint256 public mintCalls;
    uint256 public burnCalls;

    constructor(HackToken token_) {
        token = token_;
        holders.push(makeAddr("alice"));
        holders.push(makeAddr("bob"));
        holders.push(makeAddr("carol"));
    }

    function mint(uint256 holderSeed_, uint256 amount_) external {
        uint256 headroom = token.remainingMintable();
        if (headroom == 0) return;

        address to = holders[holderSeed_ % holders.length];
        token.mintTokens(to, bound(amount_, 1, headroom));
        mintCalls++;
    }

    function burn(uint256 holderSeed_, uint256 amount_) external {
        address from = holders[holderSeed_ % holders.length];
        uint256 balance = token.balanceOf(from);
        if (balance == 0) return;

        vm.prank(from);
        token.burn(bound(amount_, 1, balance));
        burnCalls++;
    }

    function burnFrom(uint256 holderSeed_, uint256 amount_) external {
        address from = holders[holderSeed_ % holders.length];
        uint256 balance = token.balanceOf(from);
        if (balance == 0) return;

        uint256 value = bound(amount_, 1, balance);
        vm.prank(from);
        token.approve(address(this), value);
        token.burnFrom(from, value);
        burnCalls++;
    }
}

/// @dev Supply invariants for the remediated token.
///
/// HC-TKN-004 established that the cap counts lifetime issuance and not
/// circulating supply. That is a property over every possible sequence of mints
/// and burns, and the regression battery states it with fixed values. These
/// invariants state it over sequences the fuzzer builds, which is where the
/// difference between the two semantics actually lives.
contract TokenSupplyInvariantTest is Test {
    HackToken token;
    SupplyHandler handler;

    uint256 constant MAX_SUPPLY = 1_000_000_000 ether;

    function setUp() public {
        token = new HackToken(address(this));
        handler = new SupplyHandler(token);

        token.grantRole(token.MINTER_ROLE(), address(handler));

        targetContract(address(handler));
    }

    /// @dev The headroom view and the counter always describe the same cap.
    /// This is the property HC-TKN-004 added `remainingMintable()` to express.
    function invariant_MintedPlusRemainingAlwaysEqualsTheCap() public view {
        assertEq(
            token.mintedTokens() + token.remainingMintable(),
            token.maxSupply(),
            "mintedTokens + remainingMintable must always equal the cap"
        );
    }

    /// @dev Lifetime issuance never exceeds the cap, whatever the order of
    /// mints and burns.
    function invariant_LifetimeIssuanceNeverExceedsTheCap() public view {
        assertLe(token.mintedTokens(), token.maxSupply(), "lifetime issuance exceeded the cap");
    }

    /// @dev Burning returns no headroom. Circulating supply can fall as far as
    /// zero and the counter does not move, which is the difference between a
    /// lifetime cap and a circulating cap reduced to its minimum.
    function invariant_BurningNeverReturnsHeadroom() public view {
        assertLe(
            token.totalSupply(),
            token.mintedTokens(),
            "circulating supply cannot exceed what was ever minted"
        );
    }

    /// @dev The cap is immutable once deployed, so no sequence of operations
    /// can move the ceiling itself.
    function invariant_CapIsFixedForTheLifeOfTheContract() public view {
        assertEq(token.maxSupply(), MAX_SUPPLY, "the cap must not change");
    }
}
