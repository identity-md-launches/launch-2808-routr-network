# Routr Network (ROUTR)

A fixed-supply ERC-20 implemented by `src/RoutrToken.sol` using vendored,
unmodified OpenZeppelin Contracts v5.1.0. All build dependencies are included as
ordinary files; no network, installation, environment variables or keys are
needed to build or test.

## Token behavior and assumptions

| Property | Value |
| --- | --- |
| Solidity contract identifier | `RoutrToken` |
| Name | `Routr Network` |
| Symbol | `ROUTR` |
| Decimals | 18 |
| Whole-token supply | 1,000,000,000 |
| Supply in base units | `1000000000000000000000000000` (10^27) |
| Constructor arguments | None |
| Initial recipient | `msg.sender`, the immediate deploying account or factory |

The constructor mints the entire supply once and emits
`Transfer(address(0), deployer, supply)`. There are no externally callable mint,
burn, pause, blacklist, seizure, ownership, configuration or upgrade functions.
The deployer has the same transfer rights as any holder after deployment.
Supply remains constant for the lifetime of this contract.

Transfers deliver exactly the requested base units, with no tax, fee, rebasing,
vesting or transfer restrictions beyond normal balance, allowance and zero-address
checks. Zero-value transfers and self-transfers are supported. Transfers to the
zero address revert rather than burn. Sending to another inaccessible address
does not reduce `totalSupply()` and may permanently lose access to those tokens.

`approve` replaces an allowance; zero revokes it. Finite allowances decrease on
`transferFrom`; the maximum uint256 approval is treated as unlimited and does not
decrease. A holder must approve even when calling `transferFrom` on their own
balance; `transfer` needs no allowance. Successful transfers/approvals return
`true`; invalid operations revert with OpenZeppelin's ERC-6093 custom errors.
Explicit approvals emit `Approval`; spending allowances does not emit another
`Approval` event in OpenZeppelin v5.1.0. Transfers always emit `Transfer`.

## Build and test

Requires Foundry and Solidity 0.8.26, pinned by version in `foundry.toml`.
Compilation uses Cancun EVM, the optimizer with 200 runs, and
`bytecode_hash = "none"`. There is no FFI or filesystem cheatcode access.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x7e933c0878ad8fe581eeb5460b99daf2d1b35e533ac0810cc5bea06e1eb6f6f0 forge test -vv
forge fmt --check
```

The self-contained test suite covers metadata, mint events, factory deployment,
exact transfers, zero values, full-balance and self-transfers, approvals,
revocation, finite/unlimited allowances, unauthorized spending, invalid addresses,
insufficient balances, transaction rollback and absent administrative selectors.
Four fuzz tests run 1,024 cases each, checking transfer conservation, delegated
spending and over-balance/over-allowance failures. Tests use fresh deployments and
do not read or modify environment variables or rely on test execution order.

The launch-flow regression models distribution, claims and token movements in
both directions with a pool account. It is a transfer-level test, not an actual
Uniswap v4 integration test. The network's supplied protected harness separately
exercises the real pool and launch process once deployment inputs are resolved.

## Deployment parameters and responsibilities

Deploy the creation bytecode for `src/RoutrToken.sol:RoutrToken` directly, with no
constructor arguments and no ETH. It makes no calls to external contracts and
requires no initialization or configuration. The immediate deployer receives
10^27 base units. Under the IdentityMD Ethereum launch this is the launch factory,
which performs the subsequent swarm distribution, pool seeding and remainder
transfer. Those actions are outside the token constructor; the token reserves no
allocation and depends on no particular router, pool manager or recipient address.

The authorized network deployer handles launch execution and the separate
manifest, checks compiled/deployed bytecode and metadata, verifies source on the
target explorer, and confirms initial balances and subsequent distribution.
No transactions have been broadcast by this project and no manifest is supplied.

## After launch

There are no owner settings, operator accounts, maintenance calls or upgrade
keys. Holders safeguard their keys, verify recipient addresses, and manage their
own spender allowances. Prefer approvals limited to the intended spend. To
change a nonzero allowance, revoke it first and wait for confirmation before
setting the new value; a spender may use an existing allowance before a pending
replacement is mined. Tokens or other assets sent to the token contract itself
have no recovery mechanism.

## Security review scope

The local source review checked the pinned security reference against the actual
implementation: the only reachable supply creation is the constructor mint;
balance and allowance changes use OpenZeppelin's checked paths; failed spends
roll back atomically; there are no external callbacks, signatures, randomness,
oracle dependencies, delegatecalls, proxies or privileged controls. Reentrancy
guards are unnecessary because token operations make no external calls. Internal
library linking is not needed and the deployed bytecode has no link placeholders.

Foundry build, unit tests, seeded fuzz tests and formatting checks are the local
validation tools. Slither and Mythril were not run. This local review and passing
tests are not an independent security audit; the contributor network's independent
review and deployment checks remain release responsibilities.
