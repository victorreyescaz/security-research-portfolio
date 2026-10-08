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
| **Published here** | 4 of the 10, the ones that are closed |

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
| [HC-SRC-004](findings/HC-SRC-004-role-registry-consistency.md) | Medium | RoleRegistry is not used consistently as the source of truth | **Published** |
| HC-SRC-005 | Medium | - | Under remediation |
| HC-SRC-006 | Medium | - | Under remediation |
| [HC-SRC-007](findings/HC-SRC-007-unregistered-recruiter-hiring-bonus.md) | Low | Monthly recruiter hiring bonus can be claimed by an unregistered recruiter | **Published** |
| HC-SRC-008 | High | - | Under remediation |
| HC-SRC-009 | Medium | - | Under remediation |
| HC-SRC-010 | Low | - | Under remediation |

Ten findings were identified in this review. The four that are closed are
documented here in full. The remaining six are published as they close, one at
a time, because publishing the detail of an open vulnerability against a
protocol that has not launched would be irresponsible. That includes the
titles, which in a review like this one describe the weakness closely enough to
be a map.

See the [disclosure policy](../../about/disclosure-policy.md) for the rules
behind that.

## The code, and what is in it

The audited contracts, the proofs of concept and the regression tests are under
[`code/`](code/). Clone the repository and `forge test` runs them.

```text
149 tests passed, 3 failed, 0 skipped (152 total tests)
```

The three failures are the proofs of concept for HC-SRC-002, HC-SRC-004 and
HC-SRC-007, kept unmodified and now reverting with `ProfileBlocked()`,
`NotEducator()` and `NotRegistered()` at the guards that closed them.

`test/exploits/` holds one proof of concept per **published** finding and
nothing else. The six still under remediation have proofs of concept too, and
they stay out. A working exploit against a vulnerability that is still open is
an attack tool, whoever publishes it and whatever the intent.

The contracts themselves are the client's and are already public in
[their own repository](https://github.com/Noahlp125/hackchain-token-contracts).
Including them here adds no exposure and makes the published findings
reproducible, which is the whole point of showing the work.

## How a finding gets closed here

A finding is not closed when the patch lands. It is closed when the original
exploit stops reproducing *for the right reason*, there is a regression test
that fails if the behaviour comes back, and the write-up is done.

The four published here did not all reach that point the same way, and the
write-ups say so. HC-SRC-002, HC-SRC-004 and HC-SRC-007 leave their original
exploits in the suite, still failing today with `ProfileBlocked()`,
`NotEducator()` and `NotRegistered()`. HC-SRC-003 could not do that, because
the remediation changed the function signatures and the old call no longer
compiles, so its red state lives in the client repository's history instead.
All four are verified. They are not all verified by the same kind of
evidence, and that is worth saying out loud.
