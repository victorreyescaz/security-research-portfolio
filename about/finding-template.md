# Finding template

The structure every finding in this repository follows. Fixed sections, in a
fixed order, so a reader can jump straight to the part they care about: a
developer to Evidence and Recommendation, a lead to Impact, a reviewer
returning months later to Verification.

`Resolution` and `Verification` stay in the template even while a finding is
open: an empty Verification section is a visible reminder that the finding is
not closed yet.

```markdown
## <FINDING-ID> - Title

Severity: Critical | High | Medium | Low | Informational
Status: Open | Resolved | Risk Accepted | Duplicate | Won't Fix
Contracts: `Contract.sol`

### Evidence

- `src/Contract.sol:line`

### Description

What is wrong and why it happens.

### Impact

What can go wrong for users, protocol funds, accounting, governance, or operations.

### Recommendation

Concrete fix direction.

### Resolution

What was changed, including PR/commit if available.

### Verification

Tests, build output, or manual checks that prove the fix.
```

## Standalone write-ups

The write-ups under `engagements/*/findings/` follow this same order and add
two sections the client report does not carry: **Proof of concept**, with the
test code and the transcript of its run, and **Residual risk**,
recording what the fix left behind: deferred design decisions, duplication
it introduced, and deployment invariants it now depends on.
