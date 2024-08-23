## Yield Aggregator

The Yield Aggregator is an open source protocol for permissionless risk curation on top of [ERC4626 vaults](https://eips.ethereum.org/EIPS/eip-4626)(strategies). Although it is initially designed to be integrated with [Euler V2 vaults](https://github.com/euler-xyz/euler-vault-kit), technically it supports any other vault as long as it is ERC4626 compliant.

The yield aggregator in itself is an ERC4626 vault, and any risk curator can deploy one through the factory. Each vault has one loan asset and can allocate deposits to multiple strategies. The aggregator vaults are noncustodial and immutable instances, and offer users an easy way to provide liquidity and passively earn yield. 

For more details, please refer to the [whitepaper](/docs/whitepaper.md) and the [low-level spec](/docs/low-level-spec.md).

## Usage

The Yield Aggregator comes with a comprehensive set of tests written in Solidity, which can be executed using Foundry.

To install Foundry:

```sh
curl -L https://foundry.paradigm.xyz | bash
```

This will download foundryup. To start Foundry, run:

```sh
foundryup
```

To clone the repo:

```sh
git clone https://github.com/euler-xyz/yield-aggregator.git
```

### Build

```shell
$ forge build
```

### Test
To run the unit-tests and the e2e test:
```shell
$ FOUNDRY_PROFILE=test forge test
```

To run the fuzz tests:
```shell
$ FOUNDRY_PROFILE=fuzz forge test
```

To run the invariants tests:
```shell
$ FOUNDRY_PROFILE=invariant forge test
```

To run foundry coverage:
```shell
$ FOUNDRY_PROFILE=coverage forge coverage --report summary
```

To run echidna based fuzzing:
```shell
$ echidna test/echidna/CryticERC4626TestsHarness.t.sol --contract CryticERC4626TestsHarness --config test/echidna/config/echidna.config.yaml
```
### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```
## Smart Contracts Documentation

```shell
$ forge doc --serve --port 4000
```

## Deployment

## Security

## License