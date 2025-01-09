# Scripts

In this directory, you can find helper `forge` scripts to interact with Euler Earn protocol.
The scripts allows to:
- Deploy Euler Earn protocol.
- Deploy a new Earn vault.
- Add strategies to an existent Earn vault.
- Remove strategies from an existent Earn vault.
- Rebalance Earn vault.
- Adjust strategies allocation points.
- Harvest

Every script takes inputs via a `ScriptName_input.json` file inside the json directory.

Before running the scripts, please make sure to fill the `.env` file following the `.env.example`. The main env variables for the script to succefully run, are `WALLET_PRIVATE_KEY` and the `NETWORK_RPC_URL`.

After filling the `.env` file, make sure to run: `source .env` in your terminal.

## Deploy Euler Earn protocol

- Fill the `DeployProtocol_input.json` file with the needed inputs.
- Run `forge script ./script/DeployProtocol.s.sol --rpc-url network_name --broadcast --slow`

## Deploy a new Earn vault

- Fill the `DeployEulerEarn_input.json` file with the needed inputs.
- Run `forge script ./script/DeployEulerEarn.s.sol --rpc-url network_name --broadcast --slow`

## Add strategies to an existent Earn vault

- Fill the `AddStrategies_input.json` file with the needed inputs.
- Run `forge script ./script/AddStrategies.s.sol --rpc-url network_name --broadcast --slow`

## Remove strategies from an existent Earn vault

- Fill the `RemoveStrategies_input.json` file with the needed inputs.
- Run `forge script ./script/RemoveStrategies.s.sol --rpc-url network_name --broadcast --slow`

## Rebalance Earn vault

- Fill the `Rebalance_input.json` file with the needed inputs.
- Run `forge script ./script/Rebalance.s.sol --rpc-url network_name --broadcast --slow`

## Adjust strategies allocation points

- Fill the `AdjustAllocationPoints_input.json` file with the needed inputs.
- Run `forge script ./script/AdjustAllocationPoints.s.sol --rpc-url network_name --broadcast --slow`

## Harvest

- Fill the `Harvest_input.json` file with the needed inputs.
- Run `forge script ./script/Harvest.s.sol --rpc-url network_name --broadcast --slow`