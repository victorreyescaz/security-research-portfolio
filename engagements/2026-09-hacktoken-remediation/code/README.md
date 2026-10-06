# HackToken: reproducible remediation environment

A self-contained Foundry project holding the `$HACK` token contract after
remediation, the proof-of-concept tests for the findings of the external audit,
the regression batteries written while fixing them, and the deployment script.
Clone the repository and it runs. No submodule initialisation, no dependency
fetch, no network.

```bash
cd engagements/2026-09-hacktoken-remediation/code
forge build
forge test
```

## Expected result

```text
55 tests passed, 0 failed, 0 skipped (55 total tests)
```

Everything is green, and no test is left failing by design. Every proof of
concept that demonstrated a vulnerability has been rewritten into the
regression that asserts the safe property instead. The evidence that the
vulnerabilities were real is commit `97ba65e` of the client repository, where
all five pass against the audited contract.

To run only the regression batteries, leaving the reproduction tests out:

```bash
forge test --no-match-path 'test/exploits/*'
# 50 tests passed, 0 failed
```

## Layout

```
src/                  the audited token contract, after remediation
script/               deployment script, multisig as admin from block one
test/exploits/        one test per reproducible finding — the map
test/regression/      one battery per finding
lib/                  vendored dependencies
```

### `test/exploits/TokenAuditValidation.t.sol`

One test per reproducible finding, five in total. Each was written to **pass**
against the audited contract, so that a green test was an unambiguous statement
of what the contract did. Each has since been rewritten into its safe
counterpart, in the commit that fixed its finding.

Each test's header records which state it is in: `SIN CORREGIR` while it still
demonstrated the vulnerability, `CORREGIDO` once it asserts the safe property.
All five now read `CORREGIDO`.

| Finding | Test | Asserts |
|---|---|---|
| HC-TKN-001 | `testCannotBurnAnotherHoldersBalanceWithoutAllowance` | a burn without the holder's allowance reverts |
| HC-TKN-002 | `testPreviousAdminRetainsNoControlAfterHandover` | the outgoing admin keeps no role and cannot grant any |
| HC-TKN-003 | `testDeployerHoldsNoRolesWhenAdminIsAnother` | the deployer holds nothing |
| HC-TKN-004 | `testBurningDoesNotFreeMintHeadroomByDesign` | burning returns no issuance headroom, deliberately |
| HC-TKN-005 | `testAdminTransferDoesNotTakeEffectWithoutAcceptance` | control moves only once the recipient accepts |

The remaining five findings (revert style, NatSpec accuracy, event indexing and
two gas issues) are not reproducible as exploits. They are covered by the
regression batteries.

### `test/regression/`

One file per finding, 50 tests.

| File | Tests | Covers |
|---|---|---|
| `TokenHCTKN001Test.t.sol` | 8 | a balance is destroyed only by its owner, or under an explicit bounded allowance |
| `TokenHCTKN002Test.t.sol` | 12 | one admin only, `owner()` ≡ `defaultAdmin()`, two-step transfer with delay and cancellation |
| `TokenHCTKN003Test.t.sol` | 10 | the deployment script refuses wrong chain, wrong address, and self-administration |
| `TokenHCTKN004Test.t.sol` | 10 | the lifetime cap holds, and burning never returns headroom |
| `TokenHCTKN006Test.t.sol` | 10 | pausing reverts with the standard error on every path, event indexing, immutable cap |

### `script/DeployHackToken.s.sol`

Deploys with the project multisig as administrator from the first block, which
is the second half of the finding about the deployer being a single point of
failure. The address is a constant in the script rather than an environment
variable: a mistyped variable on deployment day would reintroduce the finding
silently, whereas a constant is part of the diff a reviewer reads.

`preflight()` refuses to proceed on the wrong chain, against an address with no
code (the multisig not deployed there, or mistyped), or if the administrator
would be the signing key itself. `verify()` asserts the expected end state
after deployment.

## Provenance

Snapshot of the client repository `hackchain-token-contracts` at commit
`c321787`.

The version Itish audited is commit `70e6b81`. The token was untouched between
that commit and the start of this remediation, and the line numbers cited
throughout the report match it exactly.

`src/HackTokenERC20.sol` is byte-identical to the client repository. Two kinds
of edit were made elsewhere. The tests were moved into `test/exploits/` and
`test/regression/`, subdirectories that do not exist upstream, so their
relative imports changed from `../src/` to `../../src/`. And the multisig
address is replaced by a placeholder constant in `script/DeployHackToken.s.sol`
and in `TokenHCTKN003Test.t.sol`, for the reason given in the
[engagement README](../README.md#deployment-readiness).

**Compiler settings** are pinned in `foundry.toml` (`evm_version = "cancun"`,
optimizer off) so the bytecode is reproducible. They were implicit before:
Foundry proposed `prague`, solc 0.8.24 clamped it to `cancun`, and the target
was the intersection of two defaults nobody had chosen. Pinning changed no
bytecode, and deployed size is 10,847 bytes either way.

**Language note.** The contract and the tests are documented in Spanish, the
working language of the client's development team. That is the original code
and it is left as written. The engagement write-ups and this file are in
English.

## Vendored dependencies

`lib/` is committed, not resolved as a submodule or through
`forge install`. The client pins OpenZeppelin to an untagged master commit
(`5fd1781b1454fd1ef8e722282f86f9293cacf256`), so `forge install` returns
today's master instead of the code this work was done against, and a
submodule leaves `lib/` empty for anyone cloning without
`--recurse-submodules` or using GitHub's Download ZIP.

| Dependency | Included | Origin |
|---|---|---|
| OpenZeppelin Contracts | the 18 files in this contract's transitive import closure, plus `LICENSE` | commit `5fd1781b1454fd1ef8e722282f86f9293cacf256` |
| forge-std | `src/`, plus `LICENSE-APACHE` and `LICENSE-MIT` | as vendored in the client repository |

The closure changed with the remediation. `ERC20Burnable`, `ERC20Pausable`,
`AccessControlDefaultAdminRules` and its interface, `IERC5313`, `SafeCast`,
`Math` and `Panic` came in, and `Ownable` went out, because the remediation removed
the Ownable layer entirely.

Both dependencies keep their own licenses and their own copyright. See the
licensing note in the [root README](../../../README.md#permissions-and-licensing).

## On publishing this code

Every finding in this engagement is remediated, so nothing here is a working
exploit against unpatched code, which is the condition under which it is
published at all. See [the disclosure policy](../../../about/disclosure-policy.md).
