# HackToken: external audit remediation

Private engagement · Remediation of a third-party audit of the `$HACK` ERC-20
token contract · Audit report dated 2026-08-30 · Remediation started 2026-09-15

| | |
|---|---|
| **Client** | HackChain, a pre-launch Web3 platform for tech talent, education and recruitment |
| **System** | `HackTokenERC20.sol`, the `$HACK` ERC-20 token |
| **Scope** | 1 Solidity contract, 130 LoC |
| **Findings** | 10: 2 High · 3 Low · 3 Informational · 2 Gas |
| **Found by** | **Itish Audit Company** (third-party, pre-deployment review) |
| **My role** | Reproduction, verification, remediation and regression coverage |
| **Trigger** | The token could not go to public presale with two High findings open |

## What this engagement is, and what it is not

**The findings in this engagement are not mine.** HackChain commissioned an
external pre-deployment audit of the token contract from Itish Audit Company,
who delivered a report with ten findings on 2026-08-30. I was assigned the
remediation.

What I contributed is everything downstream of that report:

- **Reproduction.** The report ships no proof-of-concept code. Before changing
  anything, I wrote a Foundry test per reproducible finding, each one passing
  against the audited contract. Five of the ten findings are reproducible. The
  rest are documentation, event indexing, revert style and gas.
- **Verification against the source.** A remediation is only as good as the
  premise it is built on, so every finding was checked against what the code
  actually does before a line was changed. That check is written up in
  [`verification-of-external-findings.md`](verification-of-external-findings.md),
  and it changed the remediation of the highest-severity finding.
- **Remediation.** The fix for each finding, with its own regression battery.
- **Regression coverage.** Every proof of concept becomes a test asserting the
  safe property, so the finding cannot come back unnoticed.

## Findings and status

Severities as assigned by Itish.

| ID | Itish | Severity | Title | Status | Write-up |
|---|---|---|---|---|---|
| HC-TKN-001 | HIGH-1 | High | `BURNER_ROLE` can burn any address' balance without consent | **Verified** | [full write-up](findings/HC-TKN-001-consentless-burn.md) |
| HC-TKN-002 | HIGH-2 | High | Ownership transfer does not move role-based admin control | **Verified** | [full write-up](findings/HC-TKN-002-ownership-without-control.md) |
| HC-TKN-003 | LOW-1 | Low | Deployer receives every role, no multisig, no timelock | **Verified** | - |
| HC-TKN-004 | LOW-2 | Low | Mint cap tracks lifetime mints, never decremented on burn | **Verified** | - |
| HC-TKN-005 | LOW-3 | Low | Single-step ownership transfer, no acceptance | **Verified** | - |
| HC-TKN-006 | INFO-1 | Informational | Raw string revert in `_update()` | **Verified** | - |
| HC-TKN-007 | INFO-2 | Informational | Inaccurate NatSpec on `supportsInterface()` | **Verified** | - |
| HC-TKN-008 | INFO-3 | Informational | `TokenMinted.to` not indexed | **Verified** | - |
| HC-TKN-009 | GAS-1 | Gas | `maxSupply` should be `immutable` | **Verified** | - |
| HC-TKN-010 | GAS-2 | Gas | Redundant balance check in `burn()` | **Verified** | - |

A finding is `Verified` when the original proof of concept no longer
reproduces *for the right reason* and a regression test locks the new property
in place. It becomes `Closed`
when the external auditor's re-review confirms it, which has not happened yet.

The two High findings carry standalone write-ups because they are where the
analysis lies. In both, verifying the report against the source changed what
the right remediation was. The other eight are covered finding by finding in
[`verification-of-external-findings.md`](verification-of-external-findings.md).

**55 tests** on the token: 5 in the map file, 50 in the regression batteries.

## Two findings outside the report

Both surfaced while verifying the report against the source. Neither appears in
the Itish report nor in the client's internal task list.

- **Inherited `transferOwnership()` bypasses the custom transfer path.**
  `Ownable.transferOwnership()` remains `public virtual onlyOwner`, so an owner
  can move ownership without passing the custom function's checks and without
  emitting `TransferNewOwner`. Any indexer listening on that event misses the
  transfer. The report marked "malicious event log" as passed.
- **`mintTokens()` is pausable in effect but does not declare it.** It carries
  no `whenNotPaused`, yet `_update()` reverts while paused, so minting fails
  anyway. The declared modifiers do not describe the real behaviour.

## Deployment readiness

The contract is remediated and the deployment path is prepared, but **nothing
is deployed**. The token goes on-chain after the external auditor's re-review.

`code/script/DeployHackToken.s.sol` deploys with the project multisig as
administrator from the first block, with the address as a constant rather than
an environment variable, because a mistyped variable on deployment day would
reintroduce HC-TKN-003 silently.

The multisig was verified on-chain, not taken on trust: a Safe v1.4.1 on
Polygon (chain id 137), threshold 2 of 3, already deployed and with transactions
executed.

Its address does not appear in this repository. The token has not been deployed
yet, so the administrator address is not published ahead of time and the code
here carries a placeholder constant instead. What the script demonstrates is
that the address is a compile-time constant and not an environment variable,
and that holds whatever the value turns out to be.

Cancun opcode support was verified the same way, with `MCOPY` and `TSTORE`
executed through `eth_call` and an invalid opcode as a negative control, to
confirm the test discriminates and does not simply pass everything. Compiler
settings are pinned so the bytecode the auditor reviews is the bytecode that
ships.

## Reproducing

The contract, the proof-of-concept tests, the regression batteries and the
deployment script are under [`code/`](code/). See its README for how to run
them.
