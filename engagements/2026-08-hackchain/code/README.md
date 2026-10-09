# HackChain: reproducible audit environment

A self-contained Foundry project with the audited contracts, the proofs of
concept for the findings published here, and the regression tests written
during their remediation. Clone the repository and it runs, with no submodule
initialisation and no dependency fetch.

```bash
cd engagements/2026-08-hackchain/code
forge build
forge test
```

## Expected result

```text
185 tests passed, 6 failed, 0 skipped (191 total tests)
```

**The six failures are the point.** They are original proofs of concept for
closed findings, kept unmodified. Three revert at the guard their fix added,
and the revert reason is the evidence: a different error would mean the test
is failing for the wrong reason. The other three fail because the behaviour
they assert is gone.

To run only the tests that assert the security properties hold:

```bash
forge test --no-match-path 'test/exploits/*'
# 183 tests passed, 0 failed
```

## Layout

```
src/                  the 14 audited contracts
test/exploits/        one proof of concept per published finding
test/regression/      the tests pinning each fix, plus the project's own suite
lib/                  vendored dependencies
```

### `test/exploits/`

One file per finding, named after it. Each proof of concept is written to
**pass** against the vulnerable code, so a green test is an unambiguous
statement of what the contracts do.

| Finding | Proof of concept | Result today |
|---|---|---|
| [HC-SRC-001](../findings/HC-SRC-001-academic-cycle-accounting.md) | `testAcademicCycleAdvancesWithoutSeparatingOldViews` | adapted, passes and demonstrates the fix |
| [HC-SRC-002](../findings/HC-SRC-002-blocked-profile-enforcement.md) | `testBlockedProfileCanStillOpenAStake` | fails with `ProfileBlocked()` |
| [HC-SRC-003](../findings/HC-SRC-003-penalty-evidence-snapshot.md) | `testPenaltyCanBeAvoidedByEmptyingCurrentBalance` | adapted, passes and demonstrates the fix |
| [HC-SRC-004](../findings/HC-SRC-004-role-registry-consistency.md) | `testRevokedEducatorCanStillReceiveEducatorBonus` | fails with `NotEducator()` |
| [HC-SRC-007](../findings/HC-SRC-007-unregistered-recruiter-hiring-bonus.md) | `testUnregisteredRecruiterCanClaimMonthlyHiringBonus` | fails with `NotRegistered()` |
| [HC-SRC-011](../findings/HC-SRC-011-blocking-penalty-zero-evidence.md) | `testPenaltyWithZeroEvidenceLeavesProfileUnblocked` and one more | fail, the expected revert no longer happens |
| [HC-SRC-012](../findings/HC-SRC-012-block-ownership-by-source.md) | `testSettlingUnrelatedDebtLiftsManualBlock` | fails on its assertion |

Two could not stay red. HC-SRC-003 and HC-SRC-001 had their remediations
change the interface the exploit called, so the original no longer compiles.
Both were adapted to assert the safe behaviour, and both keep their original
form and transcript in the test file.

The findings still under remediation have proofs of concept too. They are not
here, and the reason is in the [engagement page](../README.md).

### `test/regression/`

The batteries written for each closed finding, 9 tests for HC-SRC-001, 31 for
HC-SRC-002, 3 for HC-SRC-003, 30 for HC-SRC-004, 3 for HC-SRC-007, 8 for
HC-SRC-011 and 13 for HC-SRC-012, alongside the project's own pre-existing
suite covering remediations that predate this review.

Two of them are fuzz runs rather than unit tests, on the properties where a
fixed value states too little: claim order independence in HC-SRC-001, and the
evidence balance across its whole range in HC-SRC-011.

## Provenance

Snapshot of the client repository `hackchain-token-contracts`, which is public
at [Noahlp125/hackchain-token-contracts](https://github.com/Noahlp125/hackchain-token-contracts).
`src/` is byte-identical to it. The only edits are to the relative imports of
the tests, which moved into `test/exploits/` and `test/regression/`
subdirectories that do not exist upstream.

**Language note.** The contracts and the tests are documented in Spanish, the
working language of the client's development team. That is the original code
and it is left as written. The write-ups are in English.

## Vendored dependencies

`lib/` is committed rather than resolved as a submodule or through
`forge install`. The client pins OpenZeppelin to an untagged master commit
(`5fd1781b1454fd1ef8e722282f86f9293cacf256`), so `forge install` returns
today's master rather than the code this review was performed against, and a
submodule leaves `lib/` empty for anyone cloning without `--recurse-submodules`
or using GitHub's Download ZIP.

OpenZeppelin is reduced to the transitive import closure of what these
contracts use, 24 files, each byte-identical to the pinned commit. forge-std is
vendored as the client vendors it.

Both dependencies keep their own licenses and copyright. See the licensing note
in the [root README](../../../README.md#permissions-and-licensing).
