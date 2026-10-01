# HC-TKN-001 - Any `BURNER_ROLE` Holder Could Destroy Any Balance Without Consent

| | |
|---|---|
| **Severity** | High (as assigned by the auditor) |
| **Found by** | Itish Audit Company (external pre-deployment audit, 2026-08-30) |
| **My role** | Reproduction, verification, remediation, regression coverage |
| **Status** | Remediated · pending the auditor's re-review |
| **Class** | Excessive privilege · confiscation without consent |
| **Contract** | `HackTokenERC20.sol` |
| **Reported** | 2026-08-30 |
| **Remediated** | 2026-09-16 |

## Summary

The token exposed `burn(address from_, uint256 amount_)` behind
`onlyRole(BURNER_ROLE)`. The address whose tokens were destroyed was chosen by
the caller. There was no ownership check, no allowance, no opt-in of any kind.

Any address the admin granted `BURNER_ROLE` to (a compromised key, a buggy
contract, a careless integration) could zero any holder's balance.

## Evidence

`src/HackTokenERC20.sol:76-81` in the audited version (`70e6b81`):

```solidity
function burn(address from_, uint256 amount_) public onlyRole(BURNER_ROLE) whenNotPaused {
    if (amount_ == 0) revert AmountMustBeGreaterThanZero();
    if (balanceOf(from_) < amount_) revert InsufficientBalance();
    _burn(from_, amount_);
    emit TokenBurned(from_, amount_);
}
```

## Proof of concept

The audit shipped no proof-of-concept code, so the first step was reproducing
the finding against the audited contract. This test passed before remediation:

```solidity
function testBurnerCanDestroyAnyHolderBalance() public {
    token.mintTokens(HOLDER, 10_000 ether);
    token.grantRole(token.BURNER_ROLE(), BURNER);

    assertEq(token.allowance(HOLDER, BURNER), 0, "sanity: the burner holds no allowance");

    vm.prank(BURNER);
    token.burn(HOLDER, 10_000 ether);

    assertEq(token.balanceOf(HOLDER), 0,
        "a BURNER_ROLE holder wiped a third party balance without consent");
}
```

A separate address, granted the role and holding no allowance, empties a
holder's entire balance. Committed in `97ba65e`, where it passes, and rewritten
into its safe counterpart in `f6e5de5`.

## The premise the remediation rested on

The auditor's four recommendations all preserved the capability and wrapped it
in controls: document it as an administrative penalty, restrict the role to a
purpose-built PenaltySystem behind a timelock, emit a case id, cap the amount
per call or epoch.

They rested on one sentence of reasoning:

> The comments indicate this is intentional so that a future PenaltySystem
> contract can burn tokens from penalized users.

That comment exists. `PenaltySystem` does not do what it claims.

It records each sanction against a destination and settles by transfer:

```solidity
address destination = isExternal_ ? treasury : affected_;
...
bool success = hackToken.transferFrom(msg.sender, p.destination, p.amount);
```

The penalty **redistributes** value to the treasury or to the wronged party.
Burning would destroy exactly what the mechanism is built to deliver. The
capability was not merely unused. It was incompatible with the design it was
supposedly built for.

Three further observations from the source:

- **No contract held `BURNER_ROLE`.** The identifier appeared only in the token, and
  nothing granted it anywhere in the codebase.
- **Enforcement already worked by consent.** The offender settles their own debt
  and must have approved `PenaltySystem` beforehand. The protocol's leverage is
  a profile block that bars them platform-wide until they pay, not seizure. The
  model is *blocked until you pay*, not *taken from you*.
- **The case id the report asked to add already existed**, as a first-class
  concept inside `PenaltySystem`.

## Impact

Any holder's balance could be destroyed at the discretion of any role holder.
For a token headed to a public presale, the ability to burn a buyer's tokens
without their consent is a governance risk in itself, independent of whether it
is ever used.

## Resolution

The premise being false changed what the right fix was, so the choice went to
the client and not settled on my own: keep the capability and wrap it
in controls, or remove it. The client chose removal.

The contract now inherits OpenZeppelin's `ERC20Burnable`:

```solidity
burn(uint256 value)                       // the caller's own balance
burnFrom(address account, uint256 value)  // requires the holder's allowance
```

`from_`, `BURNER_ROLE`, the `TokenBurned` event and the `InsufficientBalance`
error are gone. Net diff on the contract: +11 / −21 lines.

Two smaller calls, both toward less bespoke code. `TokenBurned` was not
preserved through an override. The standard signal for a burn is
`Transfer(holder, 0x0, value)`, which ERC20 already emits and every indexer
already understands. Zero-amount burns are not rejected: a harmless no-op, and
an override would add gas to every legitimate burn.

**Why this is a closure and not a mitigation.** With `from_` removed, no third
party can reach another holder's balance at all. An allowance is not a weaker
version of the same control. It moves the authority from the token admin to
the token holder, who grants a bounded amount and can revoke it at will.

**What was deliberately not implemented.** The report's four bullets are not
rejected, they are moot. There is no administrative burn left to document, cap,
restrict or annotate with a case id. Stated explicitly for the re-review, so it
is recorded as resolved, not as risk accepted.

## Verification

The original proof of concept no longer compiles: `BURNER_ROLE` and
`burn(address,uint256)` do not exist. It was rewritten as
`testCannotBurnAnotherHoldersBalanceWithoutAllowance`, which asserts that
`burnFrom` without an allowance reverts with `ERC20InsufficientAllowance` and
that the balance survives.

`TokenHCTKN001Test.t.sol` locks the property down with 8 tests:

| Test | Property |
|---|---|
| `BurnOnlyAffectsCallerBalance` | burning touches only the caller |
| `BurnFromRevertsWithoutAllowance` | no consent, no burn |
| `BurnFromConsumesAllowance` | the allowance is spent exactly, leaving no residue |
| `BurnFromRevertsAboveAllowance` | the allowance is a ceiling, and a failed burn spends none of it |
| `BurnRevertsAboveBalance` | holders cannot burn what they do not have |
| `BurnRevertsWhenPaused` | pausing still blocks burns |
| `BurnFromRevertsWhenPaused` | same through the integrator-facing path |
| `BurnReducesTotalSupply` | circulating supply drops, not just the balance |

## Residual risk

None on this path: the capability no longer exists.

Should HackChain ever require confiscation without consent, a decision put to
the client and declined, it would need a new mechanism, reviewed on its own
terms. An allowance cannot provide it: a holder who does not want their tokens
burned simply does not approve.

## Collateral

**HC-TKN-010**, the report's second gas finding (a balance check in `burn()`
duplicating one `_burn()` already performs), is closed by the same change. The
check and the custom error it raised lived inside the removed function.
