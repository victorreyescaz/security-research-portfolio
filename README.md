# Security Research Portfolio

Smart contract security work by **Víctor Reyes Cazorla**.
Solidity · Foundry · EVM

[![CI](https://github.com/victorreyescaz/security-research-portfolio/actions/workflows/ci.yml/badge.svg)](https://github.com/victorreyescaz/security-research-portfolio/actions/workflows/ci.yml)

Each engagement here has the analysis, a write-up for every finding, and
Foundry tests you can run yourself. If something is described here, there is a
test that shows it.

## Engagements

| Engagement | Type | Scope | Findings | Severity | Status |
|---|---|---|---|---|---|
| [HackChain](engagements/2026-08-hackchain/) | Security review, my own findings | 14 contracts, ~4,200 LoC Solidity | 10, found by me | 4 High · 4 Medium · 2 Low | 2 published · 8 under remediation |
| [HackToken](engagements/2026-09-hacktoken-remediation/) | Remediation of a third-party audit | 1 contract, 130 LoC Solidity | 10, found by Itish Audit Company | 2 High · 3 Low · 3 Informational · 2 Gas | 10 verified · re-review pending |

## How I work

A patch landing does not close a finding. It is closed when the original
exploit stops reproducing *for the right reason*, and there is a regression
test that fails if the behaviour ever comes back.

I also check the report itself. Every finding handed to me was tested against
what the code actually does before I changed a line, and in the engagement
above that check changed how the highest-severity finding was fixed.

→ [Methodology](about/methodology.md) · [Disclosure policy](about/disclosure-policy.md)

## Stack

- **Languages**: Solidity
- **Testing**: Foundry (`forge test`, fuzzing, invariant testing)
- **Focus areas**: access control and role consistency, state ownership across
  modules, reward accounting, replay and evidence uniqueness, deployment-time
  invariants

## Permissions and licensing

This work is published with the permission of HackChain, the client that
commissioned it. Third-party audit reports belonging to other firms are not
redistributed here. Where this repository covers findings from an external
audit, those findings are credited to their authors and described in my own
words.

- My own work (write-ups, proof-of-concept tests, regression tests and
  methodology) is MIT licensed, see [`LICENSE`](LICENSE).
- Client contract source remains the property of its owner and is included only
  so the tests compile and run. Its presence here does not relicense it.
- Vendored dependencies (OpenZeppelin Contracts, forge-std) keep their own
  licenses and copyright.

## Contact

victorreyes.caz@gmail.com · [GitHub](https://github.com/victorreyescaz) · [LinkedIn](https://www.linkedin.com/in/v%C3%ADctor-reyes-cazorla-75361b10b/)
