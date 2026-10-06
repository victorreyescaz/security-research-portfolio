# HC-SRC-002 - Blocked Profiles Are Not Enforced Across The Protocol

| | |
|---|---|
| **Severity** | High |
| **Status** | Resolved · closed |
| **Class** | Broken access control · split state ownership |
| **Contracts** | `RoleRegistry`, `PenaltySystem`, `StakingContract`, `ReferralSystem`, `MembershipSystem`, `TalentBonuses`, `RecruiterBonuses`, `EventRewards`, `EducatorBonuses`, `ReputationBonuses` |
| **Reported** | 2026-08-12 |
| **Resolved** | 2026-09-08 |

## Summary

`PenaltySystem` could mark a user's profile as blocked, and nothing else in
the protocol cared. The blocked flag lived in a mapping private to
`PenaltySystem`, and none of the eight business modules read it before
accepting new activity or paying out incentives.

The result: a penalty was a frontend-level restriction. Any penalized account
that interacted with the contracts directly kept staking, kept claiming
rewards, kept activating memberships and kept collecting bonuses.

## Evidence

- Blocked profile state existed only in `PenaltySystem`: `src/PenaltySystem.sol:77`
- A view exposed it: `src/PenaltySystem.sol:303`
- No other reviewed contract called `isProfileBlocked()` before a sensitive action.

## Proof of concept

`testBlockedProfileCanStillOpenAStake()` in
`test/exploits/AuditValidation.t.sol`, in the client repository:

```solidity
token.mintTokens(user, 2_000 ether);
penalties.applyEducatorInactivityPenalty(keccak256("case"), user);
assertTrue(penalties.isProfileBlocked(user));   // the protocol knows

vm.startPrank(user);
token.approve(address(staking), 1_000 ether);
staking.stake(1_000 ether, staking.ONE_MONTH());  // and does nothing about it
vm.stopPrank();

assertEq(staking.totalStakedByUser(user), 1_000 ether);
```

Against the vulnerable code this test passed. Reproduced against
pre-remediation commit `70e6b81`:

```text
Ran 1 test for test/PreFixRepro.t.sol:PreFixRepro
[PASS] testBlockedProfileCanStillOpenAStake() (gas: 7631404)
Suite result: ok. 1 passed; 0 failed; 0 skipped
```

The penalty was applied, `isProfileBlocked(user)` returned `true`, and the
same account opened a 1,000 HACK staking position in the next call.

**On this transcript.** It is a reconstruction, not the original run. The
proof-of-concept file was never committed to the client repository, so the
pre-remediation version of it no longer exists. The attack path and the
assertions are identical to the shipped proof of concept shown above. Only
the constructor wiring differs, because `PenaltySystem` and `StakingContract`
gained a `RoleRegistry` parameter in the fix. The vulnerable contract source
is not redistributed here, see the
[disclosure policy](../../../about/disclosure-policy.md). The client can
verify the run against `70e6b81` in their own repository.

Against the remediated code the same proof of concept now reverts, which is
the subject of [Verification](#verification).

## Impact

Penalties were unenforceable at the protocol layer. `PenaltySystem` recorded
the sanction, emitted the event and reported the profile as blocked, while
the chain let the sanctioned account continue to earn.

Because eight independent reward tracks were affected (staking rewards,
referral incentives, memberships, recruiter bonuses, event rewards, educator
bonuses, reputation bonuses, project funding) the penalty mechanism was
effectively decorative for anyone willing to send transactions directly. The
economic damage scales with whatever the enforcement was supposed to prevent,
and the incentive to bypass it is highest precisely for the accounts that
earned a penalty.

## Root cause

Two contracts each believed they owned the same fact.

`RoleRegistry` was designed as the protocol's registry of verified,
off-chain-attested facts about a user. Blocked status is exactly that kind of
fact, but it was written into `PenaltySystem` instead, the module that
*produces* the block rather than the module the rest of the protocol
*queries*. Nothing forced the other modules to know that a second source of
user state had appeared, so none of them consulted it.

This is the failure mode of modular protocols generally: each contract is
correct in isolation, and the invariant that spans them is enforced nowhere.

## Recommendation

Move blocked status behind a single authority every module already reads, add
a guard on the sensitive entry points, and decide explicitly which actions
stay available to a blocked user, so that the guard does not turn into a
fund lock.

## Resolution

### 1. `RoleRegistry` becomes the single source of truth

```solidity
mapping(address => bool) public blockedProfiles;

error AlreadyBlocked();
error NotBlocked();
event ProfileBlocked(address indexed account);
event ProfileUnblocked(address indexed account);

function setBlocked(address account_) external onlyRole(REGISTRAR_ROLE) {
    if (account_ == address(0)) revert InvalidAddress();
    if (blockedProfiles[account_]) revert AlreadyBlocked();

    blockedProfiles[account_] = true;

    emit ProfileBlocked(account_);
}
```

Two deliberate choices here:

- **Blocking is not a business role.** It gets its own
  `setBlocked()`/`setUnblocked()` rather than reusing
  `registerRole()`/`revokeRole()`, because "this account is sanctioned" and
  "this account is an educator" are different concepts that must never be
  able to overwrite one another. They share `REGISTRAR_ROLE` because both
  represent off-chain-verified facts written on-chain by a trusted account.
- **`setBlocked` is not idempotent on purpose.** Blocking an
  already-blocked profile reverts, so a redundant call can never silently
  mask a state the caller did not expect.

`PenaltySystem` dropped its local mapping and now reads and writes through
`RoleRegistry`, for which it must hold `REGISTRAR_ROLE`.

### 2. Eight modules read the guard

Each sensitive entry point gained the same two-line check. `StakingContract`,
the smallest of the ten contract diffs, in the relevant part:

```diff
+ IRoleRegistry public roleRegistry;
+ error ProfileBlocked();

  function stake(uint256 amount_, uint256 duration_) external nonReentrant whenNotPaused {
+     if (roleRegistry.isBlocked(msg.sender)) revert ProfileBlocked();
      if (duration_ != ONE_MONTH && duration_ != ONE_YEAR) revert InvalidDuration();
```

### 3. Exemptions: a guard, not a trap

The interesting half of the fix. Blocking every function would have converted
a sanction into a permanent fund lock, a worse bug than the one being
fixed. A blocked user must still be able to exit a position, pay a debt, and
give up a benefit they no longer want.

| Contract | Blocked | Deliberately exempt |
|---|---|---|
| `StakingContract` | `stake()`, `claimRewards()`, `activateNoCommission()` | `withdrawPrincipal()`, `deactivateNoCommission()` |
| `ReferralSystem` | `registerReferral()` (caller), `validateReferral()` (checked against the **referrer**, not the caller) | - |
| `MembershipSystem` | `activateAdvancedMembership()`, `renewAdvancedMembership()`, `activateAcademicMembership()`, `registerContentView()`, `claimEducatorRewards()` | `cancelAdvancedMembership()` |
| `TalentBonuses` | `fundProject()` | `refundContribution()` |
| `RecruiterBonuses` | `claimRegistrationBonus()`, `claimMonthlyHiringBonus()`, `claimKycBonus()` | - |
| `EventRewards` | `claimTalentAttendanceReward()`, `claimEducatorMonthlyReward()` | - |
| `EducatorBonuses` | `claimLegacyCertsBonus()`, `claimFirstTalentsBonus()` | - |
| `ReputationBonuses` | `claimBonus()` | - |
| `PenaltySystem` | - | `settlePenalty()`, paying the debt must always be possible |

`ReferralSystem.validateReferral()` deserves its own note: the guard is
applied to the **referrer**, the party who receives the incentive, not to
`msg.sender`. Guarding the caller would have been the obvious copy-paste and
would have missed the case entirely. A blocked referrer whose referral is
validated by someone else still gets paid.

`MentorshipSessions` and `CommissionSystem` were left out, matching the scope
of the original finding. `TalentBonuses.distributeToTalents()` is an
enforcer-driven payout and was scoped out of this fix.

**Fixed in**: `e7ab48f`, `3df044a`, `f58b2f9`, `6e67a49`, `a2c9651`,
`5dc02e8`, `5d8b325`, `be8f3aa`, `0faf70e`, `ec77f0a`.

## Verification

### The original exploit no longer works

```text
Ran 23 test suites: 121 tests passed, 1 failed, 0 skipped (122 total tests)

Failing tests:
Encountered 1 failing test in test/AuditValidation.t.sol:AuditValidationTemp
[FAIL: ProfileBlocked()] testBlockedProfileCanStillOpenAStake() (gas: 9069013)
```

That single failure is the point. The proof of concept now reverts with
`ProfileBlocked()`. It fails for the *correct reason*, at the guard that was
added, not because an assertion was adjusted until the suite went green.

**The exploit's attack path was deliberately left unmodified.** Its
assertions were never adjusted to accommodate the fix: it still penalizes an
account, still stakes from it, and still asserts that the stake succeeded.
Only the constructor wiring in its setup was updated, because `PenaltySystem`
and `StakingContract` both gained a `RoleRegistry` parameter that did not
exist before the remediation, and without that change the file no longer
compiles.

It stays in the suite as historical evidence that this vulnerability once
existed and is now closed, with its revert reason recorded above. Flipping
its assertions to green would have erased the only artifact proving the
vulnerable path ever existed.

### 31 regression tests pin the new rules

| File | Tests |
|---|---|
| `RoleRegistryTest.t.sol` | 7 |
| `StakingContractHCSRC002Test.t.sol` | 5 |
| `MembershipSystemHCSRC002Test.t.sol` | 6 |
| `ReferralSystemHCSRC002Test.t.sol` | 3 |
| `RecruiterBonusesHCSRC002Test.t.sol` | 3 |
| `TalentBonusesHCSRC002Test.t.sol` | 2 |
| `EventRewardsHCSRC002Test.t.sol` | 2 |
| `EducatorBonusesHCSRC002Test.t.sol` | 2 |
| `ReputationBonusesHCSRC002Test.t.sol` | 1 |

They cover the blocked paths and, equally important, the exemptions:

```text
test_HCSRC002_BlockedProfileCanStillWithdrawMaturePrincipal
test_HCSRC002_BlockedProfileCanStillDeactivateNoCommission
test_HCSRC002_BlockedProfileCanStillCancelAdvancedMembership
test_HCSRC002_BlockedProfileCanStillRefundContribution
```

Two tests pin the subtle decisions rather than the obvious ones:

- `test_HCSRC002_ValidateSucceedsWhenOnlyReferredIsBlocked`, the referral
  asymmetry. Blocking the wrong side of that pair is a silent regression that
  no other test would catch.
- `test_BusinessRolesAreIndependentFromBlockedStatus`, blocking and role
  granting cannot leak into each other, so a future refactor cannot collapse
  them back into one flag.

### Safe behaviour, confirmed

A block stops a user from creating new activity or collecting incentives. It
does not stop them from paying their debt, recovering their own funds, or
giving up a benefit they already hold.

## Residual risk

This fix makes `RoleRegistry` the single source of truth for *blocked
status*, and in doing so lays the groundwork for
[HC-SRC-004](HC-SRC-004-role-registry-consistency.md), the same class of
problem applied to *business roles*. That finding is now closed as well.

The remediation also duplicated the `IRoleRegistry` interface and a
`setRoleRegistry()` setter across eight contracts. That is a maintenance
liability: eight places to update, eight chances for one to drift. It was
accepted for this fix, since a shared base contract would have widened the diff
across all eight modules at once, and is recorded as hardening work.

Operationally, `PenaltySystem` now depends on holding `REGISTRAR_ROLE` in
`RoleRegistry`. If deployment or a later registry migration forgets that
grant, penalties revert instead of failing open. Loud failure is the right
direction, but it makes the role grant a deployment-time invariant worth
asserting in the deploy script.
