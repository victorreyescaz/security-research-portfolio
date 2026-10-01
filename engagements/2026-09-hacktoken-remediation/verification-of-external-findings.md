# Verification of the external findings

A remediation is only as good as the premise it is built on. Before changing a
line of the token, each finding in the Itish report was checked against three
sources that should agree and sometimes do not:

1. **The audit report**: what the external auditor found and what they
   recommend, bullet by bullet.
2. **The client's internal task list**: how the finding was written up for the
   team to action.
3. **The contract source**: what the code actually does.

This document records that check per finding. It exists because in the
highest-severity finding the three sources did not agree, and following the
report literally would have produced a mitigation for a capability the protocol
does not use and cannot use.

---

## HC-TKN-001 · `BURNER_ROLE` can burn any balance without consent

**Itish severity: High.** The finding itself is correct and the reproduction
confirms it.

### What the report says

The audited function took a caller-controlled address:

```solidity
function burn(address from_, uint256 amount_) public onlyRole(BURNER_ROLE) whenNotPaused {
    if (amount_ == 0) revert AmountMustBeGreaterThanZero();
    if (balanceOf(from_) < amount_) revert InsufficientBalance();
    _burn(from_, amount_);
    emit TokenBurned(from_, amount_);
}
```

Four remediation bullets: document it as an administrative penalty function,
restrict `BURNER_ROLE` to a single purpose-built PenaltySystem contract behind a
timelock or multisig, emit a reason or case-id alongside `TokenBurned`, and add a
maximum burn amount per call or per epoch.

All four preserve the capability and wrap it in controls. They rest on one
sentence of reasoning:

> The comments indicate this is intentional so that a future PenaltySystem
> contract can burn tokens from penalized users.

### What the internal task list says

The same diagnosis, and three of the four bullets: restrict the role to a single
contract under multisig control, document it as a penalty facility rather than a
voluntary burn, and cap the amount per call.

It drops the case-id, the timelock, and the per-epoch cap. The case-id is the
only one of the four that provides traceability. The other three are
preventive. Without it, a legitimate penalty burn and an arbitrary confiscation
are indistinguishable on-chain, which is precisely what the finding objects to.

### What the source says

The auditor's reasoning comes from a comment in the token contract:

```solidity
/**
 * PenaltySystem will be able to burn tokens from penalized users.
 * CHANGE 7: Added `from_` parameter to burn tokens from any address
 * (required for penalties — PenaltySystem burns tokens from the offending user)
 */
```

`PenaltySystem` does not burn. It records each sanction against a destination
and settles by transfer:

```solidity
address destination = isExternal_ ? treasury : affected_;
...
bool success = hackToken.transferFrom(msg.sender, p.destination, p.amount);
```

The penalty **redistributes** value to the treasury or to the wronged educator.
Burning would destroy exactly what the mechanism is designed to deliver to the
injured party. The capability is not merely unused. It is incompatible with the
design it was allegedly built for.

Three further observations from the source:

- **No contract holds `BURNER_ROLE`.** The identifier appears only in the token
  itself, and nothing grants it anywhere in the codebase.
- **Enforcement already works by consent.** The offender settles their own debt
  and must have approved `PenaltySystem` beforehand. The protocol's leverage is
  `isProfileBlocked()`, which keeps the profile blocked platform-wide until the
  debt is paid, not seizure. The model is *blocked until you pay*, not *taken from
  you*.
- **The case-id the report asks for already exists**, as a first-class concept
  in `PenaltySystem` (`_recordPenalty(caseId_, ...)`). The traceability the token
  lacks, the penalty system already has.

### Decision

The premise being false changes the remediation, so the choice was put to the
client, not settled unilaterally. Two options were presented: keep the
capability and wrap it in the controls the report asks for, or remove it. The
client chose removal.

The contract now inherits OpenZeppelin's `ERC20Burnable`:

```solidity
burn(uint256 value)                       // caller's own balance
burnFrom(address account, uint256 value)  // requires the holder's allowance
```

`from_`, `BURNER_ROLE`, the `TokenBurned` event and the `InsufficientBalance`
error are gone. Net diff: +11 / −21 lines.

Two smaller calls, both toward less bespoke code. `TokenBurned` was not preserved
via an override. The standard signal for a burn is `Transfer(holder, 0x0,
value)`, which ERC20 already emits and every indexer already understands.
Zero-amount burns are not rejected, since they are a harmless no-op and the
override would
add gas to every legitimate burn.

**Why this is a closure and not a mitigation:** with `from_` removed, no
third party can reach another holder's balance at all. Allowance is not a
weaker version of the same control. It moves the authority from the token
admin to the token holder, who grants a bounded amount and can revoke it.

**What was consciously not implemented**, for the re-review: the report's four
bullets are not rejected, they are moot. There is no administrative burn left to
document, cap, restrict or annotate with a case-id.

### Regression coverage

`TokenHCTKN001Test.t.sol`, 8 tests covering the property that a balance can only
be destroyed by its owner, or by a third party holding an explicit and bounded
allowance:

| Test | Property |
|---|---|
| `BurnOnlyAffectsCallerBalance` | burning touches only the caller |
| `BurnFromRevertsWithoutAllowance` | no consent, no burn, the original PoC inverted |
| `BurnFromConsumesAllowance` | the allowance is spent exactly, leaving no residue |
| `BurnFromRevertsAboveAllowance` | the allowance is a ceiling, and a failed burn spends none of it |
| `BurnRevertsAboveBalance` | holders cannot burn what they do not have |
| `BurnRevertsWhenPaused` | pausing still blocks burns, as in the audited version |
| `BurnFromRevertsWhenPaused` | same through the integrator-facing path |
| `BurnReducesTotalSupply` | circulating supply drops, not just the balance |

### Collateral: HC-TKN-010

The report's second gas finding, a balance check in `burn()` duplicating one
that `_burn()` already performs, is closed by the same change. The check lived
inside the removed function, along with the custom error it raised.

---

## HC-TKN-002 · Ownership transfer does not move admin control

**Itish severity: High.** The finding is correct.

### What the report says

`transferOwnershipCustom()` moved only Ownable's `owner()` slot.
`DEFAULT_ADMIN_ROLE` was granted once in the constructor and never touched
again, so a team handing "ownership" to a successor kept the ability to grant
itself minting rights indefinitely.

Four remediation bullets: migrate `DEFAULT_ADMIN_ROLE` inside
`transferOwnershipCustom()`, **decide explicitly whether the other roles held
by the deployer should be revoked at the same time, atomically**, alternatively
remove Ownable entirely, and document in NatSpec what the transfer does and does
not move.

### What the internal task list says

Bullets 1 and 3: move both in one transaction, or drop Ownable. It omits
bullets 2 and 4.

The omission of bullet 2 is the most consequential in the whole task list.
Implemented literally, the deployer hands over ownership and administration
**and keeps `MINTER_ROLE`**, still able to mint to the cap. The single point
of failure survives the fix, and the finding would have been closed while open.

### What the source says

`transferOwnershipCustom()` was the only function in the contract carrying
`onlyOwner`. Nothing else was gated by ownership, no contract or script read
`owner()`, and Ownable appeared in no other contract in the protocol.

So Ownable existed for one purpose: to protect the function that transferred
Ownable. Circular, and custodian of nothing.

One more thing the report did not catch: `Ownable.transferOwnership()` remained
`public virtual onlyOwner` and inherited. An owner could call it directly,
bypass the custom function's checks, and **emit no `TransferNewOwner` event**,
so an indexer listening on that event would miss the transfer. The report had
marked "malicious event log" as passed. Tracked as HC-TKN-011.

### Decision

The report offers two routes. Verifying the pinned OpenZeppelin version turned
up a third that neither document considered: `AccessControlDefaultAdminRules`,
a standard extension available in the exact commit the client pins.

It beats both. Under it, `owner()` is a view over `defaultAdmin()` as defined
by ERC-5313. Ownership and administrative control are **the same value**, so
they cannot diverge. Not because a function moves them together, which depends
on that function being used, but because there is nothing to keep in sync. The
difference between fixing the symptom and removing the possibility.

It also brings, at no cost in bespoke code:

- one administrator only, enforced, since `grantRole(DEFAULT_ADMIN_ROLE, …)` reverts
- a two-step transfer requiring the recipient to accept, which closes HC-TKN-005
- a mandatory delay before acceptance, with cancellation, which is the timelock
  the report asked for under HC-TKN-003
- `owner()` preserved for block explorers, which the plain "remove Ownable"
  route would have lost.

The delay is fixed at **three days as a `constant` in code**, not taken as a
constructor argument, so no deployment can weaken it by mistake. It is the
window in which a hostile transfer can be spotted and cancelled. An attacker
holding the admin key cannot shorten it: lowering the delay is itself subject
to a wait equal to the delay being removed.

**What the extension does not do**, and the answer to the bullet the task list
omitted: it governs `DEFAULT_ADMIN_ROLE` only. `MINTER_ROLE` and `PAUSER_ROLE`
stay with the outgoing admin until someone revokes them. Three options were
weighed: automate it in the contract, do not grant them at deployment at all,
or keep it procedural. Procedural was chosen: automating it means bespoke code
in the exact place where a standard module was adopted to avoid it, and is
wrong in cases where an outgoing admin should keep the ability to pause during
a transition. The obligation moves to the deployment runbook, and
`test_HCTKN002_HandoverDoesNotCarryMinterOrPauser` states the boundary in
writing so no runbook assumes what the code does not do.

### Regression coverage

`TokenHCTKN002Test.t.sol`, 12 tests. `owner()` mirrors `defaultAdmin()`. The
deployer holds nothing. The admin role cannot be granted or revoked directly.
Scheduling moves nothing. Acceptance before the delay fails. Only the pending
admin can accept. The incumbent can cancel. After handover the previous admin
holds no role and cannot grant any. The delay is three days. Plus the boundary
test above.

### Collateral: HC-TKN-007 and HC-TKN-011

Both close here. The inaccurate NatSpec on `supportsInterface()` went further
than the report asked: with Ownable gone only one parent implements it, so the
override is unnecessary and was **deleted**, not re-commented. And the
inherited `transferOwnership()` bypass disappears with the base class.

---

## HC-TKN-003 · Deployer receives every role

**Itish severity: Low.** The client's task list reclassifies it as important,
and that is the better calibration: for a token headed to a public presale, one
EOA holding every role is not a low risk.

### What the report says

The constructor granted all four roles to the deployer, with no multisig and no
timelock. Four bullets: deploy with a multisig as initial holder, distribute
roles to purpose-specific contracts and revoke the deployer's copies, **a
timelock on `DEFAULT_ADMIN_ROLE` actions**, and **publish the role-holder
addresses for holder transparency**.

### What the internal task list says

Bullet 1, plus an implementation decision the report does not make: add a
parameter to the constructor. It omits the timelock and the publication.

### What the source says

Confirmed: `_grantRole` called four times on `msg.sender`, once, in the
constructor.

### Decision

The constructor takes `address initialAdmin_` and grants it every role. The
deployer holds nothing once construction returns. A zero address is rejected by
the extension itself.

The timelock bullet is satisfied for administrative handover by
`AccessControlDefaultAdminRules`, adopted under HC-TKN-002. A general timelock
on every admin action is not implemented inside the token: it is resolved at
deployment by making the administrator a Safe. Recorded here rather than
silently dropped.

The publication bullet is operational and belongs to the deployment runbook.

**The code half alone would not have closed this finding.** The constructor
makes it *possible* to deploy correctly, but nothing made it *inevitable*. So the
remediation includes `script/DeployHackToken.s.sol`, with the multisig address
as a constant rather than an environment variable, because a mistyped variable on
deployment day would reintroduce the finding with nobody noticing, whereas a
constant is part of the diff the auditor reads and gives post-deployment
verification something to compare against.

The multisig was verified on-chain before writing the script, not taken
on trust: Safe v1.4.1 at `0x1111111111111111111111111111111111111111` on Polygon
(chain id 137), threshold 2 of 3, deployed and with transactions executed.

Chain support was verified the same way. Solidity 0.8.24 compiles this contract
against `cancun`, so Cancun opcodes had to be available: `MCOPY` and `TSTORE`
were executed through `eth_call` against Polygon, with an invalid opcode as a
negative control to confirm the test discriminates instead of passing
everything.

### Regression coverage

`TokenHCTKN003Test.t.sol`, 10 tests. Four assert that the script **refuses**:
wrong chain, address with no code, and the administrator being the signing key,
which is the exact shape of the finding. Four assert that its post-deployment check
rejects a token administered by the deployer, by any other address, or
pre-minted. The rest pin the end state a block-explorer review should find.

---

## HC-TKN-004 · Mint cap tracks lifetime mints, not supply

**Itish severity: Low** in the detailed findings, *Moderate* in the same
report's checklist. See the questions at the end of this document.

### What the report says

`mintTokens()` checks the cap against `mintedTokens`, a counter that only
grows, and burning reduces `totalSupply()` but not it. Three bullets: check
against `totalSupply()` if the intent is a circulating cap, document the
lifetime semantics explicitly if it is genuinely a lifetime cap, and add a
`remainingMintable()` view.

The harm described: *"as the PenaltySystem burns tokens from penalized users
and StakingContract-style rewards are minted, mintedTokens will permanently
approach maxSupply … eventually blocking all future minting."*

### What the internal task list says

All three bullets. **The only task in the list that carries the report's
remediation in full.**

### What the source says

The mechanism is exactly as described. The harm is not.

It requires two things the protocol does not have. A systematic burner:
`PenaltySystem` never burned, and after HC-TKN-001 nobody can except a holder
destroying their own balance. And minted rewards: `IncentivesPool.fundPool()`
and `StakingContract` both take tokens through `transferFrom`, so **no contract
in the protocol mints.** Rewards recycle tokens that already exist.

The project's tokenomics settle the rest. The document fixes a maximum supply
of 1,000,000,000 HACK distributed across closed buckets (team 10%, private
sale 5%, public presale 10%, public sale 15%, incentives 30%, treasury 20%,
airdrops 10%) **summing to exactly 100%**.

### Decision

Lifetime issuance cap, documented. A circulating cap is incompatible with a
closed distribution: a token minted to replace a burned one would belong to no
bucket, and the percentages would stop describing anything. Burn 50M under a
circulating cap and 50M more may be minted. Correct circulating supply,
1,050,000,000 issued in total, and a presale buyer who read "maximum supply one
billion" would be surprised.

The lifetime cap is also the strictly stronger promise: it guarantees both that
circulating supply never exceeds the cap and that issuance never does. The
circulating cap guarantees only the first.

Exhausting the cap is the intended end state, not the failure the report fears.
Minting stops, and rewards keep flowing from the pre-allocated incentives bucket.

The contract's behaviour is unchanged by this remediation. What changed is that
the semantics moved from an undocumented side effect, which is what led the
auditor to read it as a defect, to a declared property pinned by tests.
`remainingMintable()` was added. `mintedTokens` keeps its name despite being
what misled the auditor: it is public interface listed in the report, and
renaming it would break integrators for a clarity gain that NatSpec provides.

### Regression coverage

`TokenHCTKN004Test.t.sol`, 10 tests. The cap holds exactly and across separate
mints. Burning through either path returns no headroom. With circulating supply
at zero there is still none, which is the difference between the two semantics
reduced to its minimum. `mintedTokens + remainingMintable()` always equals the
cap. One test mints the seven tokenomics buckets and asserts they exhaust the
cap exactly, so that changing `maxSupply` or a percentage without revisiting
the other trips a test and never reaches deployment.

---

## HC-TKN-005 · Single-step ownership transfer

**Itish severity: Low.** Correct, and closed as a side effect of HC-TKN-002.

The report asks for `Ownable2Step` and a pending-transfer event. The task list
carries the first, and the second comes free with the extension.

The task list presents this and HC-TKN-002 as independent items without
declaring the dependency between them. They are not independent: the "remove
Ownable" route offered under HC-TKN-002 leaves this finding without an object.
Anyone planning against that document would have budgeted work that can
evaporate.

`AccessControlDefaultAdminRules` supplies the two-step transfer with acceptance
for `DEFAULT_ADMIN_ROLE`, which is now the only control the contract has. The
regressions live in `TokenHCTKN002Test.t.sol` alongside the rest of the
handover behaviour, and `testAdminTransferDoesNotTakeEffectWithoutAcceptance`
carries the finding in the map file.

---

## HC-TKN-006 to HC-TKN-010 · Informational and gas

The task list groups these as one item and carries all five correctly. Two were
closed earlier as side effects, and the other three went in together.

| | Report's ask | Resolution |
|---|---|---|
| **006** | custom error instead of the raw `require` string in `_update()` | Took the report's **second** option, which the task list omits: inherit `ERC20Pausable`. The bespoke `require` disappears and the revert becomes `EnforcedPause()`, OpenZeppelin's standard error, rather than inventing a `ContractPaused()` of our own. `_update()` survives only as a two-line disambiguation stub. |
| **007** | correct the NatSpec claiming the override exists because Ownable and AccessControl conflict | Went further: with Ownable gone only one parent implements `supportsInterface`, so the override was **deleted** rather than re-commented. Closed with HC-TKN-002. |
| **008** | index `TokenMinted.to` | Done. The event was kept, not removed, although it duplicates `Transfer(0x0, to, amount)`. The asymmetry the report cited was against `TokenBurned`, which no longer exists, but deleting public interface an integrator may already consume was nobody's request. |
| **009** | `maxSupply` as `immutable` | Done, assigned in the constructor. |
| **010** | remove the balance check in `burn()` that `_burn()` already performs | Closed with HC-TKN-001: the check and its custom error lived inside the function that was removed. |

**HC-TKN-012**, from the annex: `mintTokens()` is blocked while paused but did
not declare it. Documented in NatSpec rather than given a `whenNotPaused`
modifier, because the modifier would duplicate the check `_update()` already performs,
which is precisely the pattern the report flagged as GAS-2 and that was removed
under HC-TKN-010. Fixing one inconsistency by recreating the one just closed
would be a poor trade.

### Regression coverage

`TokenHCTKN006Test.t.sol`, 10 tests. Pausing reverts with the standard error
across transfer, `transferFrom`, mint and burn. Approvals still work while
paused, which is deliberate and worth stating, and everything resumes after
unpausing. `TokenMinted` is filterable by recipient, asserted twice, once that
the topic is emitted and once that filtering by it actually discriminates
between two mints to different addresses. The immutable cap holds its value and
is set per deployment.

---

## Questions returned to the auditor

Two issues in the report itself, raised with Itish and not resolved
unilaterally.

**Severity ratings contradict each other inside the report.** The "Issues
Checking Status" table marks item 22 (*Role-based access control vs. Ownable
separation*) as **Severe** and items 10, 11 and 23 as **Moderate**, while the
severity breakdown on the following page states **Medium: 0**. The supply-cap
issue appears as *Moderate* in the table and *Low* in the detailed findings.

**One "Moderate" is never explained.** Item 11 of the checklist, *Economy model
of the contract*, is flagged **Moderate** and has no corresponding detailed
finding anywhere in the report. Either the template was left uncleaned, or an
observation did not make it into the document.
