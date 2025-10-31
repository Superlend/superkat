# SuperKat  

**SuperKat** is a vault protocol on the **Katana blockchain**, built as a **fork of the heavily audited Euler Earn codebase**.  
It brings the robust yield-aggregator architecture of Euler to Katana, enabling users to deposit assets into managed vaults with a single entry point and earn optimized yield across underlying strategies.

---

## Overview

SuperKat allows users to deposit an underlying asset into a vault, receive vault shares in return, and benefit from yield earned through a pre-approved set of strategy vaults.  
The architecture is built on the **ERC-4626 vault standard** (or its Katana equivalent) and inherits its structure from the **audited Euler Earn** contracts.

### Key Features
- Single-asset vaults – deposit one asset, receive vault shares.  
- Curator/allocator model – separates strategic oversight and execution.  
- Risk-managed strategy caps – control exposure per strategy.  
- Transparent performance fee model – fees apply to yield, not principal.  
- Instant withdrawals.

---

## Roles & Governance

Each SuperKat vault includes distinct governance roles with clearly defined responsibilities:

| Role | Description |
|------|--------------|
| **Owner** | Primary admin (often a multisig); sets curator, allocator, guardian, fee, etc. |
| **Curator** | Selects strategy vaults, sets per-strategy caps, manages the strategy universe. |
| **Allocator** | Executes deposits and withdrawals across strategies, maintains vault balance. |
| **Guardian** (optional) | Can pause or veto critical actions for depositor protection. |
| **Fee Recipient** | Receives performance fees on yield (if applicable). |

---

## How It Works

1. User deposits an approved asset into a SuperKat vault.  
2. Vault mints shares to the depositor’s address (representing claim on underlying + yield).  
3. Assets are allocated among pre-approved strategy vaults up to configured caps.  
4. Yields from strategies increase the vault’s share price.  
5. Users can withdraw anytime, redeeming shares for underlying assets.  
6. Optional performance fees are taken on accrued yield (not on principal).

---

## Benefits of the Fork

By forking **Euler Earn**, SuperKat inherits a battle-tested and audited vault framework.  
Key inherited benefits include:

- A modular and production-proven vault architecture.  
- Separation of curator and allocator roles for governance clarity.  
- Supply/withdraw queues and caps for safe liquidity management.  
- Transparent fee accounting and yield accrual logic.  
- Compatibility with ERC-4626 for easy composability.

---

## Risks & Considerations

- **Strategy risk:** Vault yield depends on approved strategies and allocations.  
- **Liquidity risk:** Withdrawals may be delayed during low liquidity conditions.  
- **Governance risk:** Owner, curator, and allocator roles have administrative control.  
- **Smart contract risk:** Although forked from audited Euler Earn, on-chain risk remains.  

---

## Audit

This codebase is **forked from the audited Euler Earn repository**, a proven and security-reviewed vault system.  
SuperKat retains the architectural design and safety mechanisms from Euler Earn, adapted for **Katana chain deployment** by the **Superlend** team.
A list of audits can be found [here](https://github.com/Superlend/superkat/tree/main/audits)
