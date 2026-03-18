#!/usr/bin/env python3
"""Parse the provided address list into a non-testnet multi-chain manifest."""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path

CHAIN_ALIASES = {
    "ethereum": "ethereum",
    "base": "base",
    "arbitrum": "arbitrum",
    "optimism": "optimism",
    "polygon": "polygon",
    "avalanche": "avalanche",
    "bnb smart chain": "bsc",
    "zksync era": "zksync",
    "solana": "solana",
}

CHAIN_REGEX = "|".join(
    sorted((re.escape(k) for k in CHAIN_ALIASES.keys()), key=len, reverse=True)
)

EVM_RE = re.compile(r"0x[a-fA-F0-9]{40}")
SOL_RE = re.compile(r"\b[1-9A-HJ-NP-Za-km-z]{32,44}\b")
CHAIN_ONLY_ADDR_RE = re.compile(
    rf"^\s*(?P<chain>{CHAIN_REGEX})\s*[:\t ]+\s*(?P<addr>0x[a-fA-F0-9]{{40}})\s*$",
    re.IGNORECASE,
)
INLINE_CHAIN_ADDR_RE = re.compile(
    rf"(?P<chain>{CHAIN_REGEX})\s*:\s*(?P<addr>0x[a-fA-F0-9]{{40}})",
    re.IGNORECASE,
)
TAB_CHAIN_FIELD_RE = re.compile(
    rf"^[^\t]+\t(?P<chain>{CHAIN_REGEX})\t",
    re.IGNORECASE,
)
ETHERSCAN_URL_RE = re.compile(r"etherscan\.io/(?:address|token)/(0x[a-fA-F0-9]{40})", re.IGNORECASE)

NON_SECTION_HEADERS = {
    "asset\tchain\tdescription\tcontracts",
    "name\taddress",
    "admin role\taddress\ttype of key",
    "l1 contract addresses",
    "base admin addresses",
    "basenames",
    "coinbase attestations",
    "coinbase smart wallet infrastructure",
    "coinbase's validator staking infrastructure",
    "commerce payments",
    "dex aggregator",
    "eip-7702",
    "spend permissions",
    "verified pools",
    "wrapped token (ada)",
    "wrapped token (doge)",
    "wrapped token (ltc)",
    "wrapped token (xrp)",
    "wrapped tokens",
    "liqufi",
    "base <> solana bridge",
    "echo",
    "flywheel protocol",
    "recovery signer",
    "l2 contract addresses",
    "unneeded contract addresses",
    "statecommitmentchain",
    "canonicaltransactionchain",
    "bondmanager",
}


@dataclass
class Entry:
    chain: str
    address: str
    source_lines: set[int]
    labels: set[str]


def norm_chain(raw: str) -> str:
    return CHAIN_ALIASES[raw.strip().lower()]


def norm_addr(addr: str) -> str:
    return addr.lower()


def add_entry(entries: dict[tuple[str, str], Entry], chain: str, addr: str, line_no: int, label: str) -> None:
    if chain == "solana":
        normalized = addr
    else:
        normalized = norm_addr(addr)

    key = (chain, normalized)
    if key not in entries:
        entries[key] = Entry(chain=chain, address=normalized, source_lines=set(), labels=set())
    entries[key].source_lines.add(line_no)
    if label:
        entries[key].labels.add(label)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default="input/source_list.txt")
    parser.add_argument("--output", default="data/input_manifest.json")
    args = parser.parse_args()

    src_path = Path(args.input)
    text = src_path.read_text(encoding="utf-8")

    entries: dict[tuple[str, str], Entry] = {}

    in_testnet = False
    section_chain: str | None = None
    last_chain_for_followup: str | None = None

    lines = text.splitlines()
    for i, raw in enumerate(lines, start=1):
        line = raw.strip()
        if not line:
            continue

        low = line.lower()

        if "testnet" in low or "sepolia" in low:
            in_testnet = True
            section_chain = None
            last_chain_for_followup = None
            continue

        # Explicitly return to mainnet mode.
        if low in {"base mainnet", "ethereum mainnet"}:
            in_testnet = False
            section_chain = "base" if low == "base mainnet" else "ethereum"
            last_chain_for_followup = section_chain
            continue

        # Other section headers clear chain context.
        if low in NON_SECTION_HEADERS:
            section_chain = None
            if low == "l1 contract addresses":
                # Next heading will set mainnet/testnet mode and chain.
                last_chain_for_followup = None
            continue

        # If a heading appears and it's not a known data row, clear section chain.
        if "\t" not in line and not EVM_RE.search(line) and not SOL_RE.search(line):
            section_chain = None

        if in_testnet:
            continue

        # pattern: "Chain 0x..." or "Chain\t0x..."
        m = CHAIN_ONLY_ADDR_RE.match(line)
        if m:
            chain = norm_chain(m.group("chain"))
            add_entry(entries, chain, m.group("addr"), i, line)
            last_chain_for_followup = chain
            continue

        # pattern: "Base: 0x..."
        for m_inline in INLINE_CHAIN_ADDR_RE.finditer(line):
            chain = norm_chain(m_inline.group("chain"))
            add_entry(entries, chain, m_inline.group("addr"), i, line)
            last_chain_for_followup = chain

        # pattern: tabular row with chain in second column (address may be on next line)
        m_tab_chain = TAB_CHAIN_FIELD_RE.match(line)
        if m_tab_chain:
            last_chain_for_followup = norm_chain(m_tab_chain.group("chain"))

        # Etherscan URL shorthand, treat as ethereum.
        for m_url in ETHERSCAN_URL_RE.finditer(line):
            add_entry(entries, "ethereum", m_url.group(1), i, line)

        evm_addrs = EVM_RE.findall(line)
        if evm_addrs:
            # pick a chain in order: inline explicit, section, followup
            chosen_chain = None

            inline_chain_hits = [norm_chain(mh.group("chain")) for mh in INLINE_CHAIN_ADDR_RE.finditer(line)]
            if inline_chain_hits:
                chosen_chain = inline_chain_hits[-1]
            elif section_chain:
                chosen_chain = section_chain
            elif last_chain_for_followup:
                chosen_chain = last_chain_for_followup

            if chosen_chain:
                for addr in evm_addrs:
                    add_entry(entries, chosen_chain, addr, i, line)
                continue

        # Solana addresses in non-testnet sections.
        if "solana" in low:
            for s in SOL_RE.findall(line):
                if not s.startswith("0x"):
                    add_entry(entries, "solana", s, i, line)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    manifest = {
        "source": str(src_path),
        "scope": "non-testnet entries from provided list",
        "entries": [
            {
                "chain": e.chain,
                "address": e.address,
                "labels": sorted(e.labels),
                "source_lines": sorted(e.source_lines),
            }
            for e in sorted(entries.values(), key=lambda x: (x.chain, x.address))
        ],
    }

    output_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    by_chain: dict[str, int] = {}
    for e in manifest["entries"]:
        by_chain[e["chain"]] = by_chain.get(e["chain"], 0) + 1

    print(f"Parsed entries: {len(manifest['entries'])}")
    for chain in sorted(by_chain):
        print(f"  {chain}: {by_chain[chain]}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
