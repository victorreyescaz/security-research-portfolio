# Methodology

How I run a security review, and what I consider sufficient evidence at each
stage. This is the process actually followed in the engagements in this
repository, not an aspirational description.

## 1. Understand the product before reading the code

Most exploitable bugs in application-level protocols are not memory or
arithmetic bugs. They are gaps between what the product promises and what
the contracts enforce. So the first pass is product documentation, tokenomics
and intended user flows.

This is what surfaces findings like *"the documented multi-organizer payout
flow has no safe path in the code"* or *"a benefit the product advertises is
never consumed by the module that charges for it"*. No amount of pattern
matching on Solidity finds those.

## 2. Review the code, module by module and then across modules

Per contract: access control, state ownership, arithmetic, external calls,
token handling, upgrade and pause paths.

Across contracts is where modular protocols actually break. Recurring
questions I ask of every multi-contract system:

- **Single source of truth**: when a state flag exists in two contracts,
  which one wins, and does every consumer read the winner?
- **Evidence uniqueness**: can any rewarded action be replayed, or counted
  twice with a derived identifier?
- **Identity**: can one person control both sides of a two-party incentive?
- **Accounting isolation**: can one accounting bucket spend another's funds?
- **Snapshot vs. live state**: does a penalty or payout read a value the
  user can move between the triggering event and the execution?

## 3. Assess the existing test suite against each finding

Before writing anything, I read the project's own tests and record, per
finding, what they already cover and what gap remains. This matters for two
reasons: it stops me reporting something the team already controls, and it
tells the team precisely which test they are missing instead of "add more
tests".

## 4. Reproduce every finding with a runnable proof of concept

No finding ships without a Foundry test that demonstrates it against the
real code. A finding I cannot reproduce is a hypothesis, and it is reported
as one, or dropped.

Proof-of-concept tests are written to **pass** against the vulnerable code,
because a green test is an unambiguous statement: this is the behavior, here
is the transcript.

## 5. Rate severity

- **Critical**: direct loss of funds, protocol-wide insolvency, or permanent
  asset lock likely under realistic conditions.
- **High**: material economic or security risk, or a broken core invariant.
- **Medium**: exploitable weakness requiring privileged or off-chain
  conditions, or inconsistent behavior likely to cause abuse.
- **Low**: limited risk, hard-to-exploit edge case, or maintainability issue
  with minor security impact.
- **Informational**: design note, operational concern, or documentation
  improvement.

Severity is argued in the write-up, not asserted. If the impact depends on a
trusted actor misbehaving or on an off-chain condition, that is stated
explicitly and the rating reflects it.

## 6. Close the loop: fix, verify, pin

This is the part most portfolios skip, and the part that actually matters to
a team paying for a review.

```text
PoC passes before the fix    = the vulnerable behavior is reproduced
PoC fails after the fix      = first signal the vulnerable path changed
Regression test passes       = the new security rule is now enforced and pinned
```

**A failing proof of concept is not a closed finding.** It has to fail for
the right reason. The temptation is to flip an assertion until the suite goes
green again, and that produces a test that documents nothing. The discipline is:
first understand what blocked the attack, then write down which property must
hold from now on.

The original exploit is never edited to make it pass. It is kept as historical
evidence of a vulnerability that once existed, and its post-fix revert reason
is recorded in the write-up.

### States I track per finding

| State | Meaning |
|---|---|
| `PoC reproduced` | The issue is confirmed against the vulnerable code. |
| `Fix pending` | The contract has not been modified yet. |
| `Fix in progress` | Remediation is being implemented. |
| `Regression pending` | A fix exists, but the test pinning the new rule does not. |
| `Verified` | The original PoC no longer works and the regression tests pass. |
| `Closed` | Code, tests and documentation are all updated. |

## 7. Record residual risk

A closed finding often leaves something behind: a design decision deferred, a
pattern now duplicated across modules, a neighbouring finding whose
remediation the fix has just made easier or harder. Each write-up ends with
that note, so the next reviewer, or the same team in six months, starts
from where the review actually left off.

## Tooling

Foundry (`forge test`, fuzzing, invariant testing) for reproduction and
regression. Manual review is the primary instrument. Static analysis is used
as a sweep for the mechanical classes of bug, never as the review itself.

## Write-up structure

Every finding is written up against the same fixed template, so a reader
always knows where to look: → [finding-template.md](finding-template.md)
