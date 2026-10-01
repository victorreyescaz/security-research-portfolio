# HC-SRC-003 - Percentage Penalties Use Mutable Live Balances Instead Of Evidence Snapshots

| | |
|---|---|
| **Severity** | High |
| **Status** | Resolved, verified |
| **Class** | State read at the wrong time, attacker-controlled input |
| **Contracts** | `PenaltySystem` |
| **Reported** | 2026-08-12 |
| **Resolved** | 2026-09-30 |

## Summary

Six `apply*Penalty()` functions priced the fine as a percentage of
`hackToken.balanceOf(user_)`, read at the instant the enforcer's transaction
executed. The balance at execution is not the balance at the infraction, and
the gap between them belongs to the person being sanctioned.

Anyone who saw a penalty coming could move their tokens out first. The
percentage then computed to zero, the function reverted on its own
zero-amount guard, and nothing was recorded. No debt, no profile block, not
even a failed attempt in the logs.

## Evidence

- The six penalty functions in `src/PenaltySystem.sol` derived the amount from the live balance.
- `applyMassSalePenalty()` carried the same dependency in a different place: not in the amount, but in its two eligibility checks, whether the account holds at least 1% of supply and whether the sale exceeds 50% of its holdings.

## Proof of concept

`testPenaltyCanBeAvoidedByEmptyingCurrentBalance()`. Against the vulnerable
code it minted 100 HACK to the offender, moved all of it to another address,
and then called `applyEducatorInactivityPenalty()`. The call reverted, and
both `penaltyDebt(user)` and `isProfileBlocked(user)` stayed empty.

No front-running was needed. The window is not a block, it is however long
passes between an off-chain infraction and a human enforcer getting round to
sending the transaction.

## Impact

The entire penalty mechanism was opt-out for anyone paying attention.

Worse than the evasion itself is that it left no trace. A penalty that
reverts records nothing, so an operator reading the chain sees no attempt, no
failure and no reason to look again. The protocol could not tell the
difference between an account that was never sanctioned and one that dodged
every sanction it earned.

## Root cause

The contract priced a past event with a present value, and the present value
was controlled by the party being priced.

A penalty is a statement about something that already happened: at the moment
of the infraction, this account held this much. `balanceOf()` cannot answer
that question. It answers a different one, what the account holds right now,
and the two only coincide if nobody acts in between.

## Recommendation

Take the amount from evidence of the infraction, not from live state. Whatever
the enforcer verified off-chain when they decided to sanction is the figure
the contract should use.

## Resolution

The enforcer now supplies the evidence amount, and `balanceOf()` is gone from
the calculation entirely.

| Functions | New parameter |
|---|---|
| `applyIdentityFraudPenalty`, `applyNoShowPenalty`, `applyEducatorInactivityPenalty`, `applyPlagiarismPenalty`, `applyRecruiterInactivityPenalty` | `evidenceBalance_` |
| `applyMassSalePenalty` | `holdingsBeforeSale_`, replacing `balanceOf()` in both eligibility checks. `saleAmount_` and `circulatingSupply_` already came from the enforcer |

### The signature check that was deliberately not added

The obvious next question is what stops an enforcer from inventing the
evidence figure. A cryptographic signature over the evidence, verified
on-chain, was considered and rejected.

It would have been inconsistent with the trust model the protocol already
runs on. Every privileged flow here rests on `ENFORCER_ROLE`, with no on-chain
signature verification anywhere else. Adding ECDSA to this one path would
create the appearance of a cryptographic guarantee on a single function while
every neighbouring function stays role-trusted, which is worse than being
plainly role-trusted everywhere: it invites a reader to assume a property the
system does not have.

If the trust model is to change, it changes protocol-wide and as its own
piece of work.

**Commit** `f906007`, merged into `main` on 2026-09-30 via PR #2. Developed on
`fix/hc-src-003-penalty-evidence-snapshot`, stacked on the HC-SRC-002 branch.

## Verification

Three regression tests in `PenaltySystemHCSRC003Test.t.sol`:

| Test | What it holds in place |
|---|---|
| `test_HCSRC003_PenaltyUsesEvidenceAmountAfterUserMovesTokens` | moving tokens after the infraction does not change the recorded debt |
| `test_HCSRC003_MassSalePenaltyUsesHoldingsBeforeSaleNotLiveBalance` | the eligibility checks read the pre-sale holdings, not the live balance |
| `test_HCSRC003_PenaltyCaseIdCannotBeReplayed` | the same case cannot be charged twice |

`forge test` on the branch where this landed: 124 of 125 passing, with the
single failure being the HC-SRC-002 proof of concept, which is unrelated and
fails by design.

### A note on the proof of concept

Unlike HC-SRC-002, this exploit was **not** left in the suite failing. The
remediation changed the function signatures, so the original call no longer
compiles. The test was adapted to the new signature and now asserts the safe
behaviour: the enforcer supplies the pre-emptying balance of 100 HACK, a debt
of 5 HACK is recorded and the profile is blocked, even though the live balance
is zero.

That is a real difference in evidence. For HC-SRC-002 the closed path is
demonstrated by a test that still fails today. Here the red state exists only
in git history, in the commit before `f906007`. Worth saying plainly rather
than presenting both findings as if they were verified the same way.

## Residual risk

`applyIdentityFraudPenalty`, `applyMassSalePenalty` and `applyNoShowPenalty`
had no test coverage at all before this work. They now have one test each
through the new battery, which is enough to pin the evidence-amount property
but is not the depth that `PenaltySystemH04Test.t.sol` gives the functions
that were already in use. Widening that coverage is recorded as future work.

The evidence figure is only as good as the enforcer supplying it. That is a
deliberate property of the design and not a defect, but it means the control
that matters now lives off-chain, in whatever process verifies a balance
before a sanction is raised. The contract can no longer be tricked by the
offender. It can still be fed a wrong number by a compromised enforcer, which
is the same exposure every other privileged flow in the protocol already has.
