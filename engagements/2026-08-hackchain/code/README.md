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
149 tests passed, 3 failed, 0 skipped (152 total tests)

[FAIL: ProfileBlocked()]  testBlockedProfileCanStillOpenAStake()
[FAIL: NotEducator()]     testRevokedEducatorCanStillReceiveEducatorBonus()
[FAIL: NotRegistered()]   testUnregisteredRecruiterCanClaimMonthlyHiringBonus()
```

**The three failures are the point.** They are the original proofs of concept
for HC-SRC-002, HC-SRC-004 and HC-SRC-007, kept unmodified after the
vulnerabilities were fixed. Each now reverts at the guard that closed it, and
the revert reason is the evidence: a different error would mean the test is
failing for the wrong reason.

To run only the tests that assert the security properties hold:

```bash
forge test --no-match-path 'test/exploits/*'
# 148 tests passed, 0 failed
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
| [HC-SRC-002](../findings/HC-SRC-002-blocked-profile-enforcement.md) | `testBlockedProfileCanStillOpenAStake` | fails with `ProfileBlocked()`, closed |
| [HC-SRC-003](../findings/HC-SRC-003-penalty-evidence-snapshot.md) | `testPenaltyCanBeAvoidedByEmptyingCurrentBalance` | passes, and now demonstrates the fix |
| [HC-SRC-004](../findings/HC-SRC-004-role-registry-consistency.md) | `testRevokedEducatorCanStillReceiveEducatorBonus` | fails with `NotEducator()`, closed |
| [HC-SRC-007](../findings/HC-SRC-007-unregistered-recruiter-hiring-bonus.md) | `testUnregisteredRecruiterCanClaimMonthlyHiringBonus` | fails with `NotRegistered()`, closed |

HC-SRC-003 is the one that could not stay red. Its remediation changed the
function signatures, so the original call no longer compiles. The test was
adapted and now asserts the safe behaviour instead, which its write-up explains
in full.

The findings still under remediation have proofs of concept too. They are not
here, and the reason is in the [engagement page](../README.md).

### `test/regression/`

The batteries written for each closed finding, 31 tests for HC-SRC-002, 3 for
HC-SRC-003, 30 for HC-SRC-004 and 3 for HC-SRC-007, alongside the project's own
pre-existing suite covering remediations that predate this review.

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
