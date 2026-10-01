# HC-TKN-002 - Transferring Ownership Did Not Transfer Control

| | |
|---|---|
| **Severity** | High (as assigned by the auditor) |
| **Found by** | Itish Audit Company (external pre-deployment audit, 2026-08-30) |
| **My role** | Reproduction, verification, remediation, regression coverage |
| **Status** | Remediated · pending the auditor's re-review |
| **Class** | Split authority · two control systems in parallel |
| **Contract** | `HackTokenERC20.sol` |
| **Reported** | 2026-08-30 |
| **Remediated** | 2026-09-17 |

## Summary

The token carried two access-control systems at once. Ownable held `owner()`.
AccessControl held `DEFAULT_ADMIN_ROLE`, and with it every real privilege:
granting and revoking the roles that mint, burn and pause.

`transferOwnershipCustom()` moved only the first. A team handing "ownership" to
a successor multisig would reasonably believe it had handed over the contract,
while the original deployer quietly retained the ability to grant itself
minting rights, forever.

## Evidence

The constructor granted the admin role once, in the audited version
(`70e6b81`, `src/HackTokenERC20.sol:39-44`):

```solidity
constructor() ERC20("Hack Chain Token", "HACK") Ownable(msg.sender) {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    ...
}
```

And the transfer never touched it (`:87-92`):

```solidity
function transferOwnershipCustom(address newOwner_) public onlyOwner {
    require(newOwner_ != address(0), "New owner cannot be zero address");
    require(newOwner_ != owner(), "New owner must be different from current owner");
    emit TransferNewOwner(owner(), newOwner_);
    transferOwnership(newOwner_);
}
```

## Proof of concept

Reproduced against the audited contract before any change. The test does not
stop at "the role is still held". It carries the impact through to a mint:

```solidity
function testDeployerKeepsAdminRoleAfterOwnershipTransfer() public {
    token.transferOwnershipCustom(NEW_OWNER);
    assertEq(token.owner(), NEW_OWNER, "sanity: ownership moved to the new owner");

    assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), address(this)),
        "the previous owner still administers every role");

    token.grantRole(token.MINTER_ROLE(), ATTACKER);
    vm.prank(ATTACKER);
    token.mintTokens(ATTACKER, 1_000 ether);

    assertEq(token.balanceOf(ATTACKER), 1_000 ether,
        "the former owner still mints after handing over ownership");
}
```

## Root cause

Ownable protected exactly one function in this contract:
`transferOwnershipCustom()`, the function that transferred Ownable. It was
circular, and custodian of nothing. Verified: no contract or script in the
protocol read `token.owner()`, and Ownable appeared in no other contract.

Two systems existed where one was needed, and only the decorative one moved.

## A second defect the audit did not catch

`Ownable.transferOwnership()` remained `public virtual onlyOwner` and
inherited. An owner could call it directly, bypassing the custom function's
checks entirely and **emitting no `TransferNewOwner` event**. Any indexer
listening on that event would miss the transfer.

The audit had marked "malicious event log" as passed. Tracked separately as
HC-TKN-011 and closed by the same remediation.

## Impact

The deployer retained, indefinitely and invisibly, the ability to mint to the
cap after apparently relinquishing the contract. For a token entering a public
presale, the difference between what a block explorer would show (a multisig
as `owner()`) and who could actually mint is the entire risk.

## Resolution

The report offered two routes: migrate the admin role inside the custom
transfer, or remove Ownable entirely. Verifying the pinned OpenZeppelin version
turned up a third that neither the report nor the client's task list had
considered: **`AccessControlDefaultAdminRules`**, a standard extension present
in the exact commit the client pins.

```solidity
contract HackToken is ERC20, ERC20Burnable, ERC20Pausable, AccessControlDefaultAdminRules
```

Under it, `owner()` is a view over `defaultAdmin()` as defined by ERC-5313.
Ownership and administrative control are **the same value**. They cannot
diverge, not because a function keeps them in step, which depends on that
function being used, but because there is nothing to keep in step. That is the
difference between fixing the symptom and removing the possibility.

It brings four more things at no cost in bespoke code:

- exactly one administrator, enforced, since `grantRole(DEFAULT_ADMIN_ROLE, …)` reverts
- a two-step transfer the recipient must accept, closing **HC-TKN-005**
- a mandatory delay with cancellation, which is the timelock the report asked
  for under HC-TKN-003
- `owner()` preserved for block explorers, which plain removal would have lost

The delay is **three days, a `constant` in code** rather than a constructor
argument, so no deployment can weaken it by mistake. It is the window in which
a hostile transfer can be spotted and cancelled. An attacker holding the admin
key cannot shorten it: reducing the delay is itself subject to a wait equal to
the reduction.

### The bullet the client's task list omitted

The audit asked to *"decide explicitly whether MINTER_ROLE / BURNER_ROLE /
PAUSER_ROLE held by the deployer should also be revoked at the same time"*. The
internal task list dropped it. Implemented as written there, the deployer would
hand over ownership and administration and **keep `MINTER_ROLE`**, still able
to mint to the cap. The finding would have been closed while open.

The extension governs `DEFAULT_ADMIN_ROLE` only. Three options were weighed:
automate the other roles in the contract, do not grant them at deployment, or
keep it procedural. Procedural was chosen, because automating it means bespoke code in
the very place a standard module was adopted to avoid it, and is wrong where an
outgoing admin should keep the ability to pause during a transition.

The obligation moves to the deployment runbook, and a regression test states
the boundary in writing so no runbook assumes what the code does not do.

## Verification

The original proof of concept no longer compiles: `transferOwnershipCustom()`
does not exist. It was rewritten as
`testPreviousAdminRetainsNoControlAfterHandover`, which performs a full
handover and asserts the previous admin holds no role and cannot grant one.

`TokenHCTKN002Test.t.sol` pins the model with 12 tests:

**One source of truth.** `owner()` mirrors `defaultAdmin()`, the deployer
holds nothing, and the admin role can be granted neither directly nor revoked
directly.

**The transfer, step by step.** Scheduling moves nothing. Acceptance before
the delay fails. Only the pending admin can accept. The incumbent can cancel,
which is what makes the delay useful. After handover the previous admin holds
no role and cannot grant one. The delay is three days.

**The boundary.** `HandoverDoesNotCarryMinterOrPauser` asserts that the
outgoing admin *keeps* `MINTER_ROLE` and `PAUSER_ROLE`, and that the incoming
admin can revoke them. It does not describe a defect: it records, in
executable form, what the contract does not guarantee.

## Residual risk

**A handover is not complete when `acceptDefaultAdminTransfer()` returns.**
`MINTER_ROLE` and `PAUSER_ROLE` must be reviewed and revoked separately. This
is documented in the contract's NatSpec, pinned by the boundary test, and
assigned to the deployment runbook, but it is a procedural control, and
procedural controls are the ones that get skipped.

Mitigating factor: once the full tokenomics distribution is minted,
`mintedTokens` equals `maxSupply` and minting reverts regardless of who holds
`MINTER_ROLE`. Revoking it becomes defence in depth, not the only
barrier, and the end state is verifiable with a single read:
`remainingMintable() == 0`.

## Collateral

**HC-TKN-005**, single-step ownership transfer, is closed by the two-step
flow the extension provides.

**HC-TKN-007**, inaccurate NatSpec claiming the `supportsInterface()` override
existed because Ownable and AccessControl conflict, went further than the
report asked. With Ownable gone only one parent implements it, so the override
was **deleted** instead of re-commented.

**HC-TKN-011**, the inherited `transferOwnership()` bypass described above,
disappears with the base class.
