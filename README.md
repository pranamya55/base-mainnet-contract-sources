# Base Ecosystem Non-Testnet Contract Sources

Snapshot of verified contract source artifacts for the address list you provided, scoped to **non-testnet entries** across chains.

## Scope

- Input list file: `input/source_list.txt`
- Scope rule: include non-testnet rows (`mainnet` / non-Sepolia), include all chains present
- Generated at (UTC): `2026-03-18T16:57:10+00:00`

## Coverage

- Input manifest entries: `238`
- Total fetched entries (includes discovered proxy implementations): `273`
- Proxy implementation edges discovered: `38`
- Unresolved proxies: `2`
- Failures: `0`

Fetched entries by chain:

- `arbitrum`: `12`
- `avalanche`: `5`
- `base`: `173`
- `bsc`: `9`
- `ethereum`: `49`
- `optimism`: `14`
- `polygon`: `7`
- `solana`: `2`
- `zksync`: `2`

## Output Layout

- `data/input_manifest.json`: normalized non-testnet manifest from your list
- `data/summary.json`: fetch summary, proxy edges, unresolved proxies, and index
- `data/contracts/<chain>/<address>/metadata.json`: explorer metadata + fetch info
- `data/contracts/<chain>/<address>/abi.json`: parsed ABI (when available)
- `data/contracts/<chain>/<address>/source/...`: extracted source files (when verified)

Notes:

- `solana` entries are included as metadata records only (non-EVM; no Solidity source fetch).
- Some addresses are EOAs or unverified contracts and therefore have no verified source.

Unresolved proxies in this snapshot:

- `base:0x043ac8dbd2f0e932800210260f207806650c6145`
- `base:0xc6d566a56a1aff6508b41f6c90ff131615583bcd`

This repository contains a static snapshot of fetched artifacts.
