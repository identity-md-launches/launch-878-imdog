# IMDog (IMDOG)

IMDog is an immutable ERC-20 token. Its constructor mints **1,000,000,000 tokens with 18 decimals** to `msg.sender`, exactly once. The total supply in minor units is **1000000000000000000000000000** (`10^27`).

## Contract and assumptions

- Contract: `src/IMDog.sol:IMDog`.
- Name: `IMDog`; symbol: `IMDOG`; decimals: `18`.
- Constructor arguments: none (`[]`); encoded arguments: `0x`; deployment value: `0`.
- The immediate creator receives the entire supply. For a factory deployment, the factory receives it, not the transaction origin or requester.
- Transfers deliver the exact amount. There are no taxes, rebases, transfer restrictions, external callbacks, or burn functions. Zero-value and self-transfers follow normal ERC-20 behavior.
- There is no owner, minter, pause, blacklist, confiscation, initializer, proxy, or upgrade mechanism. The deployer has no continuing privilege over other holders.
- `transfer`, `approve`, and `transferFrom` return `true` on success and revert with standard ERC-20 custom errors on failure. The zero address is invalid as a sender, recipient, or spender.
- Finite allowances are reduced by spending; `type(uint256).max` represents an unlimited allowance and is not reduced. Explicit approvals emit `Approval`; allowance consumption does not emit an additional `Approval` event. Transfers, including constructor minting, emit `Transfer`.

## Reproducible local checks

Install Foundry and make Solidity **0.8.26** available in its compiler cache before working offline. All Solidity dependencies are included as ordinary files in `lib/`: OpenZeppelin Contracts **v5.4.0** (ERC-20 dependency subset) and forge-std **v1.9.7** (test utilities). Each includes upstream licenses and provenance in `UPSTREAM.md`. No package installation, network, RPC, environment variables, FFI, or filesystem cheatcode access is required by the build or tests once the compiler is available.

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins the compiler, Cancun EVM target, optimizer at 200 runs, and `bytecode_hash = "none"`. Use the same settings for deployed bytecode verification. Build outputs and caches are disposable.

The tests cover metadata, constructor mint events and supply, CREATE2 factory ownership, exact transfers and event emission, approvals and revocation, delegated spending, zero/self/full-balance transfers, unlimited allowances, invalid recipients, insufficient balances/allowances, rollback of failed spending, unsupported mint/admin calls, and forbidden runtime opcodes. Four fuzz tests run 512 cases each. A stateful invariant runs 256 sequences of 64 transfer/approval/spending operations and checks total supply, balance conservation, exact movement, and allowance accounting. Every test creates its own state and requires no shared environment.

The launch-flow test checks token transfer legs (factory forwarding, distributor claims, and transfers to/from a pool address). It does **not** simulate Uniswap pricing, liquidity accounting, or swaps. The supplied protected launch harness depends on the network's factory/pool infrastructure and manifest parameters, which are not provided in this empty project. Its full integration checks remain the launch verifier's responsibility.

## Deployment and operations

Build the artifact `out/IMDog.sol/IMDog.json`. For a factory, use its creation bytecode without appended constructor parameters. This read-only command displays it:

```sh
forge inspect src/IMDog.sol:IMDog bytecode
```

The deployer must select a Cancun-compatible chain and the intended creator address. A factory using CREATE2 must also choose the salt and predict the address from that factory, salt, and exact creation bytecode. The deployment tests exercise this path without a wallet or RPC. Do not use a proxy: the supply is initialized in the constructor.

The network's launch factory is responsible for subsequent distribution, including the specified 10% swarm allocation, pool funding, and requester remainder. This token itself performs no allocation beyond minting to its creator. No chain addresses, pool parameters, opening valuation, or requester destination were supplied; these must be resolved by the launch operator. The test's 50% pool allocation is illustrative and is not a deployment parameter. No application contracts are required by this token request.

Before release, the operator must verify the deployed source/bytecode and check `name()`, `symbol()`, `decimals()`, `totalSupply()`, the mint event, and subsequent factory distribution. The creator controls the initial inventory and is responsible for custody and distribution. Holders control their balances and approvals; prefer approvals limited to the intended spend and revoke unused approvals. Changing an existing nonzero allowance carries the usual ERC-20 transaction-ordering risk; reset it to zero and confirm before granting a replacement when appropriate.

There are no ongoing administrator transactions or maintenance requirements. Mistaken transfers, lost keys, and assets sent to the token contract have no recovery mechanism. Ordinary native-currency payments revert. This project does not access wallet keys or broadcast transactions.

The local review checks the applicable security-reference concerns: constructor-only minting, exact units and transfers, authorization through caller balances/allowances, atomic reverts, and absence of external calls or privileged paths. Foundry unit, fuzz, invariant, build, and formatting checks are the validation tools used here; Slither and Mythril have not been run. Passing tests are not a security audit. Independent adversarial review and the network's full pool integration checks remain release responsibilities.
