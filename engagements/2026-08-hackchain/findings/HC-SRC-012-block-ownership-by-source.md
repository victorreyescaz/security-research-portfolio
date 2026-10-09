# HC-SRC-012 - Settling A Penalty Debt Lifted A Block Somebody Else Had Set

| | |
|---|---|
| **Severity** | Medium |
| **Status** | Resolved, closed |
| **Class** | Shared mutable flag with multiple writers |
| **Contracts** | `RoleRegistry`, `PenaltySystem` |
| **Reported** | 2026-10-08 |
| **Resolved** | 2026-10-09 |

## Summary

`RoleRegistry` stored the blocked state as a single boolean per account. Any
holder of `REGISTRAR_ROLE` could clear it, including one that had not set it.

`PenaltySystem` lifted the block whenever a user's debt reached zero. So an
offender blocked by an operator for one reason, identity fraud say, only had
to settle an unrelated penalty debt to have that manual block cleared for
them. The block that mattered was removed by paying off the one that did not.

## Evidence

- `RoleRegistry` held one flag per account: `mapping(address => bool) blockedProfiles`.
- `setBlocked()` and `setUnblocked()` were open to any `REGISTRAR_ROLE`, with no record of which one acted.
- `PenaltySystem.settlePenalty()` called `setUnblocked()` on reaching zero debt, without checking whether its own case was the reason the profile was blocked.

## Proof of concept

`testSettlingUnrelatedDebtLiftsManualBlock()` in
[`code/test/exploits/HC-SRC-012.t.sol`](../code/test/exploits/HC-SRC-012.t.sol).
An operator blocks a profile directly through the registry. A separate,
unrelated penalty is then applied and settled. The assertion that fails is the
one that says the manual block is still there.

## Impact

Any block set outside `PenaltySystem` was revocable by the account it was set
against, at the cost of settling an unrelated debt. Blocking is the protocol's
enforcement mechanism, so this is a bypass of the mechanism by the party it is
aimed at.

It also runs in the other direction. A block set by `PenaltySystem` could be
cleared by any other registrar, so the debt could survive without the block
that backs it.

Rated Medium: it needs an existing block from a second source, and an
unrelated debt to settle, which is state an unprivileged user cannot create
alone. What it removes is the guarantee that a block stays until the party who
imposed it lifts it.

## Root cause

One flag, several writers, no ownership. The registry recorded *that* an
account was blocked and never *who* said so, so every writer's view of the
flag was the same view and the last writer won.

HC-SRC-002 made `RoleRegistry` the single source of truth for blocked status,
which was right. What it did not do was give the value an owner, and a single
source of truth with several writers and no ownership is a shared mutable
variable.

The bug became reachable through HC-SRC-011. That fix introduced blocks with
no debt attached, which made "debt reached zero" an even weaker proxy for
"this block should be lifted" and put the question under a light.

## Recommendation

Record the block per source. Let each writer set and clear only its own, and
report the account as blocked while any source holds one.

## Resolution

`RoleRegistry` now keys the block by source:

```solidity
/// @notice user => origen => ese origen mantiene un bloqueo sobre el
/// perfil (HC-SRC-002, por origen desde HC-SRC-012).
mapping(address => mapping(address => bool)) private _blockedBy;

/// @notice user => número de orígenes que lo mantienen bloqueado.
mapping(address => uint256) public blockCount;
```

`isBlocked()` stays the question the eight business modules ask, and is true
while `blockCount` is above zero, so none of them changed. `isBlockedBy()` is
the new question a writer asks about its own block. The events carry the
source.

`PenaltySystem` now reads and writes only its own:

```diff
- if (!roleRegistry.isBlocked(user_)) revert ProfileNotBlocked();
+ if (!roleRegistry.isBlockedBy(user_, address(this))) revert ProfileNotBlocked();
```

Two consequences worth stating, because neither is obvious:

**It now adds its block even when the profile is already blocked.** Before, it
skipped the call to avoid a double-block revert. Under per-source ownership
that would have left the debt unbacked the moment the other source lifted
theirs.

**`adminUnblock()` was added** for a source that can no longer clear its own
block, a lost or rotated key. Without it, per-source ownership turns an
orphaned block into a permanent one.

**Fixed in**: `35779d5`.

## Verification

### The original exploit no longer works

```text
Encountered 1 failing test in test/exploits/HC-SRC-012.t.sol:HCSRC012PoC
[FAIL: el bloqueo manual se levanta al pagar una deuda que no lo puso] testSettlingUnrelatedDebtLiftsManualBlock()
```

The proof of concept was left unmodified, still asserting that the manual
block is gone after settlement. It now fails on that assertion, which is the
record that the behaviour existed.

### 13 regression tests across two files

`RoleRegistryHCSRC012Test.t.sol` pins the registry: the profile stays blocked
until every source lifts, a registrar cannot lift another source's block,
`isBlockedBy()` reports each source separately, the admin can lift an orphaned
one, `adminUnblock()` reverts when the source holds no block, only the admin
can use it, and the events carry the source.

`PenaltySystemHCSRC012Test.t.sol` pins the consumer: a manual block survives
settlement, the penalty system's own block is still lifted on settlement, it
adds its block over a manual one, `unblockProfile()` lifts only its own and
reverts without it, and the HC-SRC-011 manual flag does not outlive the block
it describes.

That last one is the seam between the two findings, and it is the test most
likely to catch a future regression in either.

## Residual risk

`blockCount` is an unbounded counter of sources. In practice the registrars
are a small fixed set, but nothing in the contract caps them, and a profile
blocked by many sources needs each one to act.

`adminUnblock()` gives the admin the ability to clear any source's block. That
is the point, and it is also a privilege worth watching: the admin can
unilaterally undo an enforcement decision it did not make. It is gated by the
admin role and emits with the source, so it is visible on-chain.
