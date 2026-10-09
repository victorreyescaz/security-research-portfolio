# HC-SRC-001 - Academic Reward Pool Accounting Could Mix Cycles And Produce Unfair Payouts

| | |
|---|---|
| **Severity** | High |
| **Status** | Resolved, closed |
| **Class** | Accounting over mutable shared state |
| **Contracts** | `MembershipSystem` |
| **Reported** | 2026-08-12 |
| **Resolved** | 2026-10-09 |

## Summary

Academic memberships pay educators out of a shared pool, proportionally to the
content views they received. The accounting kept one pot and one set of view
counters, and `advanceCycle()` did not separate them:

```solidity
mapping(address => EducatorViews) public educatorViews;
uint256 public totalViewsThisCycle;
uint256 public pendingEducatorPool;
```

After advancing the cycle, the previous cycle's views were still live and the
pool still held fees that belonged to it. What an educator received therefore
depended on when they claimed, on which fees happened to arrive before they
did, and on how many other educators had claimed first.

## Evidence

- `educatorViews` and `totalViewsThisCycle` were not reset or snapshotted by `advanceCycle()`.
- `pendingEducatorPool` was a single balance with no association to a cycle.
- `currentCycle` existed but governed nothing in the payout calculation.

## Proof of concept

`testAcademicCycleAdvancesWithoutSeparatingOldViews()` in
[`code/test/exploits/HC-SRC-001.t.sol`](../code/test/exploits/HC-SRC-001.t.sol).
A user activates an academic membership and registers one view for an
educator. The cycle is advanced. Against the vulnerable code, both
`educatorViews(educator)` and `totalViewsThisCycle()` still returned 1, so the
closed cycle's view was still competing for the open cycle's pool.

```text
[PASS] testAcademicCycleAdvancesWithoutSeparatingOldViews() (gas: 6967357)
```

Run against `42cc60b`, the last commit before the fix.

## Impact

Two educators with identical work in the same cycle could be paid different
amounts, decided by claim order and by the timing of unrelated membership
payments.

The direction of the error is not bounded by anything the contract checks. An
educator claiming late, after new fees have entered the pot, takes a share of
money that belongs to a later cycle. An educator claiming early, before the
cycle's own fees have all arrived, is underpaid. Neither case reverts, and
neither is visible without reconstructing the order of events off-chain.

Rated High because it is the core payout path of a whole product mechanism,
the amounts are wrong rather than merely delayed, and no privileged access is
needed to trigger it. Ordinary use produces it.

## Root cause

A cycle is a period that ends. The contract modelled it as a counter that
increments, with all the accounting living in variables that span every
period.

`advanceCycle()` moved the counter and nothing else, so nothing was actually
closed. The data that the payout formula reads, the pool and the view counts,
kept changing after the period they described was over.

## Recommendation

Give each cycle its own accounting, freeze it when the cycle closes, and pay
only against closed cycles.

## Resolution

Each cycle now owns its numbers:

```solidity
struct Cycle {
    uint256 pool;
    uint256 totalViews;
    uint256 claimed;
    uint256 closedAt;
    bool rolledOver;
}

mapping(uint256 => Cycle) public cycles;
mapping(uint256 => mapping(address => uint256)) public educatorCycleViews;
mapping(uint256 => mapping(address => bool)) public rewardsClaimed;
```

`advanceCycle()` closes the current cycle and freezes its pool and view
totals. Claims are only accepted against closed cycles, once per educator per
cycle. Fees paid after a cycle closes land in the open one and cannot change
what the closed one pays.

Two cases that a snapshot model has to answer, and the fix answers both rather
than leaving them to chance:

**A closed cycle with no views** has a pool and nobody to pay. It rolls that
pool forward to the next cycle instead of stranding it.

**A share nobody claims** cannot sit in a closed cycle forever. After
`UNCLAIMED_ROLLOVER_WINDOW`, fixed at 90 days, what is left can be moved to
the open cycle. Before the window, or against an open cycle, the call reverts.

**Fixed in**: `e57753e`.

## Verification

### The proof of concept

Unlike HC-SRC-002, HC-SRC-004 and HC-SRC-007, this exploit could not be left
in the suite failing. The remediation removed `educatorViews()` and
`totalViewsThisCycle()`, the two getters it read, so the original test no
longer compiles.

It was adapted to the per-cycle interface and now asserts the safe behaviour:
the old view is frozen in cycle 0, the open cycle starts at zero views, and
the two do not mix. The original form and its passing transcript are recorded
in the test file itself, so what it used to prove is not lost.

This is the same situation as HC-SRC-003, and it is worth being explicit about
it: of the seven findings published here, five are evidenced by an exploit
that still fails today, and two by an exploit that had to change shape. They
are not verified by the same strength of evidence.

### 9 regression tests, one of them a fuzz run

`MembershipSystemHCSRC001Test.t.sol` covers what the original report asked
for and what the new model added: advancing starts with zero live views,
closed-cycle rewards are unchanged by new membership fees, claim order does
not change the allocation, the open cycle cannot be claimed, the same cycle
cannot be claimed twice, a cycle without views rolls its pool forward, an
unclaimed share rolls over after the window, and neither an early rollover nor
one against an open cycle is accepted.

`testFuzz_HCSRC001_ClaimsAreProportionalAndOrderIndependent` is the one that
carries the finding itself. Order independence is a property over every
permutation of claims, and a unit test can only state it for the orders its
author thought of.

## Residual risk

The rollover window is a `constant` at 90 days. That is deliberate, since a
configurable window would let an admin shorten it and take an unclaimed share
early, but it also means changing it needs a redeployment.

Rolling an unclaimed share forward is a decision about somebody else's money.
It is gated and time-boxed, and an educator who claims within the window is
unaffected, but it remains a path by which a share earned in one cycle is paid
to the educators of another.
