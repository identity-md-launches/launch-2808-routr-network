# ROUTR test properties

The existing `RoutrToken.t.sol` remains intact. `RoutrTokenProperties.t.sol` adds
regressions and seven fuzz properties with 1,024 cases each.
`RoutrTokenInvariants.t.sol` checks three invariants after each action in 256
random sequences of 128 handler calls. Its inline configuration makes unexpected
handler reverts fail the campaign; expected token reverts are caught and their
complete custom-error data is checked inside the handler.

The suite uses native Foundry interfaces and the already vendored OpenZeppelin
contracts. It needs no additional packages, network, fork, FFI, or environment
configuration. All actors are local test accounts.

## Property selection

The five discovery perspectives lead to the following guarantees. They are based
on the requested fixed supply, the ERC-20 interface, and this implementation's
documented allowance semantics, rather than assumptions about a pool or vault.

| Perspective | Property and basis | Check |
| --- | --- | --- |
| Conservation | The constructor's sole mint is exactly `10^27` base units to its immediate deployer (`src/RoutrToken.sol:9-12`). Transfers cannot create or destroy that supply. | Constructor log regression; `invariant_fixedSupplyEqualsAllTrackedBalances` |
| State transitions | Transfers move exactly their requested amounts; approvals replace previous permissions; successful delegated spending consumes finite allowances and preserves unlimited ones (`ERC20.transfer`, `approve`, `transferFrom`, `_spendAllowance`). Reverted calls preserve balances and permissions. | Per-action assertions; both ledger invariants; atomic rollback and cumulative-spending fuzz tests |
| Round trips | Sending an amount out and back restores both balances exactly; splitting a transfer does not change its total cost or receipt. No conversion or rounding is needed for base-unit transfers. | `roundTrip` handler; split-versus-combined fuzz oracle; repeated full-supply delegated round trip |
| Adversarial inputs | Self-transfers still require sufficient balance; repeated spending cannot exceed approval; the deployer cannot mint, seize, burn, or freeze tokens. Valid full-balance movements must succeed. | Over-balance and over-allowance handlers; administration probes; full-balance and self-recipient regressions |
| ERC-20 properties | Zero-value movements succeed and emit `Transfer`, invalid zero recipients/spenders revert, zero-address balance stays zero, and metadata stays constant. | Boundary regressions, `invalidAddress`, supply/metadata invariant |

## Handler and independent ledger

`handlers/RoutrTokenHandler.sol` deploys the real token in its constructor and
distributes the known initial supply equally to five actors. The deployer is one
of those actors. Finite and unlimited approvals are seeded, while other actor
pairs start without permission.

Every transfer recipient belongs to that closed account set or is the token
contract itself. The token contract is a tracked sink and is never impersonated
to send or approve tokens. Thus summing all six balances covers every reachable
token holding in this campaign.

Ghost balances start from the specified allocation and change only for authorized
successful transfers. Ghost allowances change only on explicit approvals and
successful delegated spends. They are never populated from observed balances or
allowances. Comparing these ledgers with all balances and all account pairs can
detect unauthorized redistribution even when the total supply stays correct.
Zero-address permissions are checked separately.

Eleven targeted actions mix ordinary transfers, self-transfers, round trips,
approval overwrites and revocation, existing and fresh delegated permissions,
insufficient balances, insufficient allowances, invalid addresses, and unsupported
administration. Amount generation explicitly includes zero, one base unit, whole
balances, arbitrary partial amounts, and the uint256 maximum in rejection paths.
No input is discarded with `vm.assume` and no handler silently skips empty actors.
The deterministic handler regression pins every action and boundary mode without
requiring random campaigns to satisfy probabilistic coverage thresholds.

## Run

From the repository root:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x7e933c0878ad8fe581eeb5460b99daf2d1b35e533ac0810cc5bea06e1eb6f6f0 forge test -vv
```

The supplied protected launch checks refer to the network's factory and Uniswap
contracts, which are not part of this token repository. These additions exercise
the token locally; the existing launch-flow regression is also a transfer-level
check. No RPC or launch parameters are guessed by this suite.
