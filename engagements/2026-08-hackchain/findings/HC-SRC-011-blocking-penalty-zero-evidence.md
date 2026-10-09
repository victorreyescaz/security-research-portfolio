# HC-SRC-011 - A Blocking Penalty Could Not Be Applied To An Offender Holding No Tokens

| | |
|---|---|
| **Severity** | Medium |
| **Status** | Resolved, closed |
| **Class** | Enforcement coupled to an attacker-controlled precondition |
| **Contracts** | `PenaltySystem` |
| **Reported** | 2026-10-06 |
| **Resolved** | 2026-10-09 |

## Summary

Three of the six `apply*Penalty()` functions block the offender's profile. All
six computed the fine as a percentage of an evidence balance and then refused
to continue if the result was zero:

```solidity
uint256 penalty = (evidenceBalance_ * EDUCATOR_INACTIVITY_PENALTY_PERCENT) / 100;
if (penalty == 0) revert AmountMustBeGreaterThanZero();
```

That revert happened before `_recordPenalty()`, the only place in the protocol
that calls `RoleRegistry.setBlocked()`. So an offender whose evidence balance
rounded the percentage to zero was not fined and, more importantly, **was not
blocked**. With a 5% rate that is any balance below 20 wei, but the case that
matters is zero: nothing requires a user to hold `$HACK` in order to use the
platform, teach a course, or commit the conduct these penalties exist to
punish.

This finding came out of verifying the HC-SRC-003 remediation, not from the
initial review.

## Evidence

- `applyEducatorInactivityPenalty`, `applyPlagiarismPenalty` and `applyRecruiterInactivityPenalty` are the three penalties that block.
- All six carried the same zero-amount guard ahead of `_recordPenalty()`.
- `_recordPenalty()` held the only call to `RoleRegistry.setBlocked()` in the codebase.

## Proof of concept

[`code/test/exploits/HC-SRC-011.t.sol`](../code/test/exploits/HC-SRC-011.t.sol),
two tests. The first takes the case that needs no setup at all:

```solidity
// El infractor no posee HACK. Nada obliga a tenerlo para usar la plataforma.
assertEq(token.balanceOf(user), 0);

vm.expectRevert(PenaltySystem.AmountMustBeGreaterThanZero.selector);
penalties.applyEducatorInactivityPenalty(keccak256("case"), user, 0);

assertFalse(registry.isBlocked(user), "el perfil queda sin bloquear");
```

The second does the same with 19 wei, which at 5% also rounds to zero. Both
passed against the vulnerable code.

## Impact

The profile block is the protocol's enforcement mechanism. HC-SRC-002 made it
effective across the eight business modules, and the token remediation argued
explicitly that the model is *blocked until you pay* rather than seizure. That
leverage did not reach an account with an empty balance, and emptying an
account is free.

A debt of zero is the correct outcome for a zero balance. Skipping the block
is not, because the block is not proportional to anything. It is the part of
the sanction that does not depend on what the offender owns.

Rated Medium rather than High because `RoleRegistry.setBlocked()` is callable
by any holder of `REGISTRAR_ROLE`, so an operator could block the account by
hand. What failed was the automated path, which turned an on-chain guarantee
back into a manual step that nobody was told to take.

## Root cause

One guard was doing two jobs. `penalty == 0` is a sensible refusal for a
transfer of value, and the function reused it as the refusal for the whole
sanction. The block and the debt were never separate decisions, so a condition
that only makes sense for the debt silently governed the block as well.

## Recommendation

Separate them. Refusing a zero-value debt is fine. The block should not depend
on the amount.

## Resolution

The zero-amount guard was removed from the three blocking penalties, and kept
on the three that do not block, where a zero debt genuinely has no effect.

A zero-amount case now records no debt and creates no pending case, because
there is nothing to settle. Instead it marks the profile:

```solidity
// Importe cero solo llega aquí desde una penalización bloqueante
// (HC-SRC-011). No hay deuda que liquidar, así que no se crea caso
// pendiente y el bloqueo pasa a depender del enforcer.
if (amount_ == 0) {
    manualUnblockRequired[user_] = true;
} else {
    penaltyDebt[user_] += amount_;
    pendingPenalties[caseId_] = PendingPenalty({ ... });
}
```

### The second problem the fix had to solve

Removing the guard alone would have left the block unliftable in one direction
and liftable in the wrong one. `settlePenalty()` lifted the block when the
debt reached zero, and a zero-amount case starts at zero debt, so the very
next settlement of any unrelated case would have cleared it.

`manualUnblockRequired` closes that. While it is set, settling debt does not
lift the block, and only the enforcer's `unblockProfile()` can, which also
clears the flag.

That is the whole shape of the fix: a sanction with nothing to pay cannot be
discharged by paying, so it is discharged by the party that imposed it.

**Fixed in**: `a3e6233`.

## Verification

### The original exploit no longer works

```text
Encountered 2 failing tests in test/exploits/HC-SRC-011.t.sol:HCSRC011PoC
[FAIL: next call did not revert as expected] testPenaltyRoundingToZeroLeavesProfileUnblocked()
[FAIL: next call did not revert as expected] testPenaltyWithZeroEvidenceLeavesProfileUnblocked()
```

Both proofs of concept were left unmodified. They assert that the call reverts
and that the profile stays unblocked, and neither is true any more. The
failure reason is the generic one rather than a named error, because the
remediation did not replace the revert with a different revert. It removed it,
and the call now succeeds and blocks.

### 8 regression tests, plus the fuzz run

`PenaltySystemHCSRC011Test.t.sol` covers the three blocking penalties with
zero evidence, dust evidence recording a block without debt, that a
zero-amount case cannot be settled, that settling another case does not lift
the manual block, that the enforcer's unblock clears the flag, and that the
non-blocking penalties still reject a zero amount.

`PenaltySystemFuzzTest.t.sol` carries the property across the full input
range. `testFuzz_HCSRC011_BlockingPenaltiesBlockBelowRoundingThreshold` is the
inverted form of the test that found this: it used to assert the profile stayed
unblocked below the threshold, and now asserts it is blocked for any evidence
at all.

That inversion is the point of keeping a fuzz test rather than deleting it.
The three unit tests written for HC-SRC-003 used 10,000 and 100,000 ether,
values that never approach the boundary where the percentage rounds to zero,
which is why this survived that remediation.

## Residual risk

A zero-amount block can only be lifted by the enforcer. If the enforcer key is
lost or rotated, those blocks outlive the party that can clear them. That case
is what HC-SRC-012 addresses on the registry side, with an admin path for an
orphaned source.

The evidence figure is still supplied by the enforcer. The contract can no
longer be defeated by the offender holding nothing, but it can be fed a wrong
number by a compromised enforcer, which is the exposure every privileged flow
in this protocol already carries.
