// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { HackToken } from "../../src/HackTokenERC20.sol";

/// @dev The cap guard in `mintTokens()`, exercised across the whole input
/// range instead of at values chosen by hand.
///
/// The invariant run only ever mints within the available headroom, because a
/// handler that reverted on most calls would explore nothing. The guard itself
/// therefore needs its own coverage, and the interesting part of a guard is the
/// side of the boundary the happy path never visits.
contract TokenMintBoundaryFuzzTest is Test {
    HackToken token;

    address constant TO = address(0xBEEF);

    function setUp() public {
        token = new HackToken(address(this));
    }

    /// @dev Nothing above the remaining headroom is ever minted. The assertion
    /// is on the property, that issuance does not move, and not on a specific
    /// error: past a certain size `mintedTokens + amount_` overflows and
    /// Solidity reverts with a panic before the cap check is reached. Both
    /// outcomes refuse the mint, which is what matters here.
    function testFuzz_MintAboveHeadroomNeverIssues(uint256 preMint_, uint256 excess_) public {
        uint256 cap = token.maxSupply();
        preMint_ = bound(preMint_, 1, cap - 1);
        token.mintTokens(TO, preMint_);

        uint256 headroom = token.remainingMintable();
        excess_ = bound(excess_, 1, type(uint256).max - headroom);

        vm.expectRevert();
        token.mintTokens(TO, headroom + excess_);

        assertEq(token.mintedTokens(), preMint_, "a refused mint must not move lifetime issuance");
        assertEq(token.remainingMintable(), headroom, "a refused mint must not move the headroom");
    }

    /// @dev The boundary itself is inclusive: exactly the remaining headroom
    /// mints, and exhausts the cap.
    function testFuzz_MintingExactlyTheHeadroomExhaustsTheCap(uint256 preMint_) public {
        uint256 cap = token.maxSupply();
        preMint_ = bound(preMint_, 1, cap - 1);
        token.mintTokens(TO, preMint_);

        token.mintTokens(TO, token.remainingMintable());

        assertEq(token.mintedTokens(), cap, "the cap must be reachable exactly");
        assertEq(token.remainingMintable(), 0, "no headroom must remain");
    }

    /// @dev One past the boundary is refused with the contract's own error,
    /// which is the case the overflow never masks.
    function testFuzz_OneAboveTheHeadroomIsRefusedWithTheCapError(uint256 preMint_) public {
        uint256 cap = token.maxSupply();
        preMint_ = bound(preMint_, 1, cap - 1);
        token.mintTokens(TO, preMint_);

        // El valor se resuelve antes de armar expectRevert: una llamada de
        // vista dentro de los argumentos consumiria la expectativa.
        uint256 oneAbove = token.remainingMintable() + 1;

        vm.expectRevert(HackToken.MaxSupplyExceeded.selector);
        token.mintTokens(TO, oneAbove);
    }
}
