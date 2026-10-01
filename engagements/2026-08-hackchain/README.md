# HackChain: internal security review

Private engagement. Security review of the `$HACK` token contract suite.
Review date 2026-08-12.

| | |
|---|---|
| **Client** | HackChain, a pre-launch Web3 platform for tech talent, education and recruitment |
| **System** | The modular implementation of the platform's tokenomics around the `$HACK` ERC-20 |
| **Scope** | 14 Solidity contracts, around 4,200 LoC |
| **Findings** | 10: 4 High · 4 Medium · 2 Low · 0 Critical |
| **Found by** | Me. This is my own review, not a remediation of someone else's |
| **Published here** | 2 of the 10, the ones whose remediation is merged |

## What this engagement was

HackChain had built the token mechanics as a set of independent modules.
Staking, memberships, referrals, penalties, commissions and six separate reward
tracks, coordinated by a central `IncentivesPool` and a `RoleRegistry`. The
contracts compiled, 81 tests passed, and every module looked healthy on its
own.

The review went after the place that kind of architecture actually fails,
which is the seams between the modules. Almost every finding comes from a rule
that one contract enforces and another does not, or from state that two
contracts each believe they own.

No Critical issue was found. The dominant risk was that rules the product
promises were being enforced by trusted off-chain actors instead of by on-chain
invariants, which means they were not really being enforced at all.

Every finding was reproduced with a Foundry proof of concept before it was
reported. None of them is a theoretical concern.

## Findings

| ID | Severity | Title | Status |
|---|---|---|---|
| HC-SRC-001 | High | - | Under remediation |
| [HC-SRC-002](findings/HC-SRC-002-blocked-profile-enforcement.md) | High | Blocked profiles are not enforced across the protocol | **Published** |
| [HC-SRC-003](findings/HC-SRC-003-penalty-evidence-snapshot.md) | High | Percentage penalties use mutable live balances instead of evidence snapshots | **Published** |
| HC-SRC-004 | Medium | - | Under remediation |
| HC-SRC-005 | Medium | - | Under remediation |
| HC-SRC-006 | Medium | - | Under remediation |
| HC-SRC-007 | Low | - | Under remediation |
| HC-SRC-008 | High | - | Under remediation |
| HC-SRC-009 | Medium | - | Under remediation |
| HC-SRC-010 | Low | - | Under remediation |

Ten findings were identified in this review. The two whose fixes are merged are
documented here in full. The remaining eight are published as they close, one
at a time, because publishing the detail of an open vulnerability against a
protocol that has not launched would be irresponsible. That includes the
titles, which in a review like this one describe the weakness closely enough to
be a map.

See the [disclosure policy](../../about/disclosure-policy.md) for the rules
behind that.

## Why there is no code here

This engagement publishes write-ups and no contract source, which is the one
place where it differs from the HackToken engagement in this repository.

The reason is the overlap. The contracts that the two closed findings touch,
`RoleRegistry`, `PenaltySystem`, `StakingContract` and `MembershipSystem`,
still carry open findings of their own. Publishing enough code to make the two
proofs of concept runnable would mean publishing contracts that are vulnerable
by other routes, which is exactly what the condition above rules out.

Both write-ups carry the reproduction, the transcript, the applied fix and the
regression tests that hold it in place. What is missing is the ability to run
them yourself, and that comes back as the surrounding findings close.

For an engagement in this repository that you can clone and run, see
[HackToken](../2026-09-hacktoken-remediation/).

## How a finding gets closed here

A finding is not closed when the patch lands. It is closed when the original
exploit stops reproducing *for the right reason*, there is a regression test
that fails if the behaviour comes back, and the write-up is done.

The two published here reached that point differently, and the write-ups say
so. HC-SRC-002 leaves its original exploit in the suite, still failing today
with `ProfileBlocked()`. HC-SRC-003 could not do that, because the remediation
changed the function signatures and the old call no longer compiles, so its red
state lives in git history instead. Both are verified. They are not verified by
the same kind of evidence, and that is worth saying out loud.

→ [Methodology](../../about/methodology.md)
