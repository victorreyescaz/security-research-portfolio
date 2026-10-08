# HC-SRC-004 - RoleRegistry Is Not Used Consistently As The Source Of Truth

| | |
|---|---|
| **Severity** | Medium |
| **Status** | Resolved · closed |
| **Class** | Inconsistent authorization · split state ownership |
| **Contracts** | `MembershipSystem`, `EducatorBonuses`, `EventRewards`, `ReputationBonuses`, `TalentBonuses`, `RecruiterBonuses` |
| **Reported** | 2026-08-12 |
| **Resolved** | 2026-10-06 |

## Summary

HackChain has a `RoleRegistry` that records who is a verified Talent, Educator
or Recruiter. Its own documentation names it the single source of truth every
module must consult before granting a benefit tied to a role. Only two modules
consulted it, and one of them only in a single function.

`MembershipSystem` kept a private `EDUCATOR_ROLE` of its own.
`RecruiterBonuses` kept its own registration flag, which the registry had no
way to revoke. Three more reward modules checked no business role at all and
paid whatever address the enforcer sent. Revoking an educator in
`RoleRegistry` therefore changed nothing in most of the protocol. The revoked
account kept accruing rewards and kept getting paid.

## Evidence

- `RoleRegistry` exists as the business-role registry: `src/RoleRegistry.sol:21`
- `MentorshipSessions` consulted it: `src/MentorshipSessions.sol:97`
- `TalentBonuses` consulted it in `fundProject()` only, not in the two functions that pay talents: `src/TalentBonuses.sol:168`
- `MembershipSystem` used a local `EDUCATOR_ROLE` instead: `src/MembershipSystem.sol:22`
- `RecruiterBonuses` used its own `isRegistered` flag, independent of the registry.
- `EducatorBonuses`, `EventRewards` and `ReputationBonuses` verified no business role on-chain and relied on `ENFORCER_ROLE` sending a correct address.

## Proof of concept

`testRevokedEducatorCanStillReceiveEducatorBonus()`:

```solidity
registry.registerRole(educator, RoleRegistry.BusinessRole.Educator);
registry.revokeRole(educator, RoleRegistry.BusinessRole.Educator);
assertFalse(registry.isEducator(educator));      // the registry says no

bonuses.rewardApiIntegration(educator);           // the bonus module pays anyway

assertEq(token.balanceOf(educator), bonuses.API_INTEGRATION_REWARD());
```

Run against the last commit before the fix, `c321787`:

```text
Ran 2 tests for test/AuditValidation.t.sol:AuditValidationTemp
[PASS] testRevokedEducatorCanStillReceiveEducatorBonus() (gas: 7399158)
[PASS] testUnregisteredRecruiterCanClaimMonthlyHiringBonus() (gas: 7647820)
Suite result: ok. 2 passed; 0 failed; 0 skipped
```

The second test is the proof of concept for
[HC-SRC-007](HC-SRC-007-unregistered-recruiter-hiring-bonus.md), fixed
alongside this one.

The account was registered, revoked, confirmed as not an educator by the
registry, and then paid the 50,000 HACK API integration bonus in the next
call.

The payout function is `rewardApiIntegration()`, which only the enforcer can
call. That detail shaped the fix. The gap was not only in the functions users
call to claim. It was in the enforcer-side functions that pay or record
progress directly, which is where a revoked role is most likely to slip
through, because nothing on-chain asks the question.

## Impact

Revocation did not work. The protocol could take a role away in the registry
and keep paying the account in every module that did not read it.

For a platform whose product is verified credentials and reputation, that is
the core promise failing quietly. An educator removed for cause kept earning
educator bonuses. A talent whose status was withdrawn kept collecting
attendance and hiring rewards. A recruiter revoked in the registry kept
accruing activity days and claiming bonuses, because the recruiter module had
its own registration flag and never looked anywhere else.

The finding is Medium rather than High because every affected path needs the
enforcer to send the address, so an unprivileged user cannot trigger it
alone. But the enforcer is a backend acting on off-chain data, and the whole
point of an on-chain registry is that a stale or mistaken backend call cannot
override it.

## Root cause

The same fact had several owners.

`RoleRegistry` was built to answer "is this account an educator". Then
`MembershipSystem` answered the same question with its own role, and
`RecruiterBonuses` answered "is this account a recruiter" with its own
registration flag. The remaining modules did not ask at all. Each choice was
locally reasonable, and together they meant there was no single place where
revoking a role took effect.

It is the same failure mode as
[HC-SRC-002](HC-SRC-002-blocked-profile-enforcement.md), which fixed it for
blocked status. This finding is the same class of problem applied to business
roles.

## Recommendation

Use `RoleRegistry` for every business-role eligibility check, keep
`AccessControl` for protocol permissions only (admin, enforcer, distributor),
and avoid duplicating business roles inside individual modules unless there is
a strong reason.

## Resolution

Every business-role check now goes through `RoleRegistry`, on both sides of
each reward flow: the enforcer-side functions that pay or record progress,
and the claim functions called by the beneficiary.

| Contract | Change |
|---|---|
| `MembershipSystem` | The local `EDUCATOR_ROLE` is removed. `registerContentView()` and `claimEducatorRewards()` call `isEducator()` |
| `EducatorBonuses` | `rewardApiIntegration()`, `registerLegacyCert()`, `claimLegacyCertsBonus()`, `registerActiveTalent()`, `claimFirstTalentsBonus()` and `rewardTalentHired()` require `isEducator()` |
| `EventRewards` | Talent attendance requires `isTalent()`, educator events require `isEducator()`, both when recording and when claiming |
| `ReputationBonuses` | `registerWinner()` requires the winner to hold the role being rewarded, and `claimBonus()` checks it again |
| `TalentBonuses` | `rewardSchoolingDegree()` and `rewardTalentHired()` require `isTalent()`, matching what `fundProject()` already did for sponsors |
| `RecruiterBonuses` | Every function that registers, accumulates or pays requires `isRecruiter()` in addition to the module's own `isRegistered` |

`MentorshipSessions` already consulted `RoleRegistry` and needed no change.

### 1. A local role removed, not mirrored

`MembershipSystem` could have kept `EDUCATOR_ROLE` and been told to keep it in
sync with the registry. That would have left two sources of truth and a
synchronization duty nobody enforces. The role was removed instead:

```diff
- bytes32 public constant EDUCATOR_ROLE = keccak256("EDUCATOR_ROLE");
+ error NotEducator();

  function claimEducatorRewards() external nonReentrant {
      if (roleRegistry.isBlocked(msg.sender)) revert ProfileBlocked();
-     if (!hasRole(EDUCATOR_ROLE, msg.sender)) revert InvalidAddress();
+     if (!roleRegistry.isEducator(msg.sender)) revert NotEducator();
```

### 2. Two enums in a different order

`ReputationBonuses` has its own role enum, `UserRole { Talent, Educator,
Recruiter }`. `RoleRegistry.BusinessRole` declares `{ Educator, Talent,
Recruiter }`. Converting one into the other by index would check a Talent
winner against the Educator role, and the compiler would not object.

Reordering one enum to match the other was considered and rejected. It would
work today, and it would leave an invisible dependency between two contracts
that breaks silently the first time someone adds a role to one and not the
other. The check goes through the registry's named view functions instead,
so the order of either enum no longer matters:

```solidity
function _hasRegistryRole(UserRole role_, address account_) internal view returns (bool) {
    if (role_ == UserRole.Talent) return roleRegistry.isTalent(account_);
    if (role_ == UserRole.Educator) return roleRegistry.isEducator(account_);
    return roleRegistry.isRecruiter(account_);
}
```

The role is checked when the enforcer registers the winner and again when
the winner claims, because the claim window is three days long and a role can
be revoked inside it.

### 3. An additive check where the local flag means more than a role

`RecruiterBonuses` keeps its own `isRegistered`. It is an onboarding record
with activity days and KYC state attached, not just a role flag, so replacing
it would have been a redesign beyond this finding. The fix is additive: both
checks must pass. Revoking the role in the registry now stops the recruiter
from accruing activity, having hirings recorded, being KYC-verified and
claiming any of the three bonuses, even while `isRegistered` stays true.

### 4. A deliberate exemption

`EventRewards.rewardPromoEvent()` pays the organizer of a promotional event
and was left without a role check on purpose. The mechanism does not tie
organizers to any business role, and anyone who meets the conditions may
organize one. Forcing it into Talent, Educator or Recruiter would have
invented a restriction the product never had. A regression test pins the
exemption so it is not "fixed" later by accident.

**Fixed in**: `8442779`, `32a2277`, `2871ecf`, `7285f12`, `f3be9b5`, `42cc60b`.

## Verification

### The original exploit no longer works

```text
Failing tests:
Encountered 1 failing test in test/exploits/HC-SRC-004.t.sol:HCSRC004PoC
[FAIL: NotEducator()] testRevokedEducatorCanStillReceiveEducatorBonus() (gas: 7667933)
```

The proof of concept now reverts with `NotEducator()`, at the check that was
added to `rewardApiIntegration()`. It fails for the correct reason, and like
the one for HC-SRC-002 it was left in the suite unmodified, still asserting
that the payment succeeds, as the record that the vulnerable path existed.

After the fix the full suite passes except for three proofs of concept, those
of HC-SRC-002, this finding and
[HC-SRC-007](HC-SRC-007-unregistered-recruiter-hiring-bonus.md), each
reverting with the error its own fix introduced.

### 30 regression tests pin the new rules

| File | Tests |
|---|---|
| `MembershipSystemHCSRC004Test.t.sol` | 3 |
| `EducatorBonusesHCSRC004Test.t.sol` | 7 |
| `EventRewardsHCSRC004Test.t.sol` | 7 |
| `ReputationBonusesHCSRC004Test.t.sol` | 4 |
| `TalentBonusesHCSRC004Test.t.sol` | 3 |
| `RecruiterBonusesHCSRC004Test.t.sol` | 6 |

They cover addresses that never held the role, roles revoked between
accumulating and claiming, and the positive path for accounts that do hold
the role. Four of them pin decisions rather than obvious behaviour:

- `test_HCSRC004_EachRoleIsCheckedAgainstItsOwnRegistryRole` crosses all
  three reputation roles against each other. A mix-up between the two enums
  fails here and nowhere else.
- `test_HCSRC004_WinnerRevokedBeforeClaimCannotClaim` revokes the role inside
  the three-day window, between registration and claim.
- `test_HCSRC004_RevokedRecruiterCannotAccumulateActivity` keeps
  `isRegistered` true and revokes only the registry role, which is exactly
  the state the additive check exists for.
- `test_HCSRC004_PromoEventOrganizerNeedsNoBusinessRole` pays an organizer
  with no role at all, holding the exemption in place.

### Safe behaviour, confirmed

Revoking a role in `RoleRegistry` takes effect immediately in every module
connected to it, both for accumulating progress and for collecting rewards.

## Residual risk

The enforcer is still trusted for everything other than the role. The
contract now refuses to pay an account that does not hold the right role, but
whether the activity being rewarded really happened is still decided
off-chain. That is the protocol's trust model, not something this fix
changes. Other parts of what the enforcer-side functions leave open relate to
findings still under remediation and not published yet.

A winner whose role is revoked during the claim window cannot be replaced.
`registerWinner()` allows one winner per role per month, so that month's
bonus for the role goes unclaimed and stays in the pool rather than passing to
another account. Failing closed is the right default here, but it is a
product decision worth confirming.

`RecruiterBonuses` now has two records to keep in step. Onboarding a recruiter
needs both the registry role and the module's registration, and an operator
who grants only one will see the other's error. That is loud, which is good,
but it makes both grants part of the onboarding procedure.

A local `IRoleRegistry` interface is now declared in ten contracts, each with
the slice it uses, and the `setRoleRegistry()` setter is repeated in nine of
them. Consolidating them into a shared base contract is recorded as
separate hardening work, kept out of this fix so the security diff stays
reviewable on its own.
