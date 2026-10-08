# HC-SRC-007 - Monthly Recruiter Hiring Bonus Can Be Claimed By An Unregistered Recruiter

| | |
|---|---|
| **Severity** | Low |
| **Status** | Resolved · closed |
| **Class** | Missing authorization check |
| **Contracts** | `RecruiterBonuses` |
| **Reported** | 2026-08-12 |
| **Resolved** | 2026-10-06 |

## Summary

`RecruiterBonuses` pays three bonuses to recruiters, and keeps an
`isRegistered` flag to make sure only onboarded recruiters receive them. Four
of its entry points checked the flag. The two that drive the monthly hiring
bonus, `registerHiring()` and `claimMonthlyHiringBonus()`, did not.

An address that was never registered could have hirings recorded against it
and then collect the 40,000 HACK monthly bonus, while the registration and KYC
bonuses next to it were correctly closed to it.

## Evidence

- Registration state exists: `src/RecruiterBonuses.sol:52`
- `recordActivity()` checks registration: `src/RecruiterBonuses.sol:133`
- `claimKycBonus()` checks registration: `src/RecruiterBonuses.sol:252`
- `claimMonthlyHiringBonus()` does not: `src/RecruiterBonuses.sol:206`

## Proof of concept

`testUnregisteredRecruiterCanClaimMonthlyHiringBonus()`:

```solidity
for (uint256 i = 0; i < 4; i++) {
    bonuses.registerHiring(user, keccak256(abi.encode("talent", i)));
}

assertFalse(bonuses.isRegistered(user));   // never registered
vm.prank(user);
bonuses.claimMonthlyHiringBonus();           // paid anyway
assertEq(token.balanceOf(user), bonuses.MONTHLY_HIRING_BONUS());
```

Run against the last commit before the fix, `c321787`:

```text
Ran 2 tests for test/AuditValidation.t.sol:AuditValidationTemp
[PASS] testRevokedEducatorCanStillReceiveEducatorBonus() (gas: 7399158)
[PASS] testUnregisteredRecruiterCanClaimMonthlyHiringBonus() (gas: 7647820)
Suite result: ok. 2 passed; 0 failed; 0 skipped
```

The first test is the proof of concept for
[HC-SRC-004](HC-SRC-004-role-registry-consistency.md), fixed alongside this
one.

Four distinct hiring IDs were recorded for an address the contract itself
reports as unregistered, and that address then claimed the full monthly
bonus.

## Impact

The registration and KYC flow could be bypassed for one of the three bonuses,
the only one that pays every month. Eligibility was inconsistent inside a single
contract: the same address was refused the registration bonus and paid the
hiring bonus.

The finding is Low because the enforcer has to record the hirings first. An
unprivileged user cannot create the required state alone. What it removes is
the on-chain backstop for an enforcer mistake, such as a hiring attributed to
the wrong address or to a recruiter whose onboarding was never completed.

## Root cause

The check existed and was applied by hand to each entry point, and two entry
points were missed. Nothing in the contract made registration a precondition
of the monthly hiring flow as a whole, so its absence did not show up until
someone traced each path separately.

## Recommendation

Require `isRegistered` on both monthly hiring paths: `registerHiring()` for
the recruiter being credited, and `claimMonthlyHiringBonus()` for the caller.

## Resolution

Both checks were added as recommended:

```diff
  function registerHiring(address recruiter_, bytes32 talentId_) external onlyRole(ENFORCER_ROLE) {
      if (recruiter_ == address(0)) revert InvalidAddress();
+     if (!isRegistered[recruiter_]) revert NotRegistered();
      ...
  }

  function claimMonthlyHiringBonus() external nonReentrant {
      if (roleRegistry.isBlocked(msg.sender)) revert ProfileBlocked();
+     if (!isRegistered[msg.sender]) revert NotRegistered();
      ...
  }
```

### Fixed together with HC-SRC-004

[HC-SRC-004](HC-SRC-004-role-registry-consistency.md) adds a `RoleRegistry`
recruiter check to these same functions, and on its own that check would also
have stopped this proof of concept, but with the registry's error rather than
the one this finding calls for. The `isRegistered` check runs first in each
function, so the proof of concept fails through its own fix, `NotRegistered()`.

**Fixed in**: `82fee06`.

## Verification

### The original exploit no longer works

```text
Failing tests:
Encountered 1 failing test in test/exploits/HC-SRC-007.t.sol:HCSRC007PoC
[FAIL: NotRegistered()] testUnregisteredRecruiterCanClaimMonthlyHiringBonus() (gas: 7803044)
```

The proof of concept reverts with `NotRegistered()` at the first
`registerHiring()` call. It was left in the suite unmodified, still asserting
that the bonus is paid, as the record that the vulnerable path existed.

### 3 regression tests

`RecruiterBonusesHCSRC007Test.t.sol`:

| Test | What it holds in place |
|---|---|
| `test_HCSRC007_UnregisteredRecruiterCannotHaveHiringRegistered` | the enforcer cannot credit hirings to an unregistered address |
| `test_HCSRC007_UnregisteredRecruiterCannotClaimMonthlyHiringBonus` | an unregistered caller is refused before the hiring count is even read |
| `test_HCSRC007_RegisteredRecruiterCanStillClaimAfterFourHirings` | the legitimate flow still pays |

The setup registers the recruiter in `RoleRegistry` from the start, so these
tests isolate the missing local registration and do not depend on the
registry check added by HC-SRC-004.

### Safe behaviour, confirmed

An unregistered address can neither have hirings recorded nor claim the
monthly bonus. A registered recruiter still collects it after four hirings.

## Residual risk

With the first check in place, an unregistered address can no longer reach
four recorded hirings through the public API, so the claim-side check cannot
be triggered today. It is kept as defence in depth, in case the way hirings
accumulate ever changes.

`RecruiterBonuses` has no function to unregister a recruiter. Taking a
recruiter out of the flow now goes through revoking the role in
`RoleRegistry`, which the HC-SRC-004 fix made effective in this contract.
