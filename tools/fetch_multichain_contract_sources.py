#!/usr/bin/env python3
"""Fetch multi-chain verified contract sources from a manifest."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import time
from collections import deque
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

EIP1967_IMPLEMENTATION_SLOT = (
    "0x360894A13BA1A3210667C828492DB98DCA3E2076CC3735A920A3CA505D382BBC"
)

EVM_ADDRESS_RE = re.compile(r"^0x[a-fA-F0-9]{40}$")

CHAIN_CONFIG: dict[str, dict[str, Any]] = {
    "ethereum": {"kind": "etherscan_v2", "chainid": "1"},
    "base": {"kind": "etherscan_v2", "chainid": "8453"},
    "arbitrum": {"kind": "etherscan_v2", "chainid": "42161"},
    "optimism": {"kind": "etherscan_v2", "chainid": "10"},
    "polygon": {"kind": "etherscan_v2", "chainid": "137"},
    "bsc": {"kind": "etherscan_v2", "chainid": "56"},
    "avalanche": {"kind": "etherscan_v2", "chainid": "43114"},
    "zksync": {"kind": "zksync_explorer", "api_url": "https://block-explorer-api.mainnet.zksync.io/api"},
}

ETHERSCAN_V2_API = "https://api.etherscan.io/v2/api"


def now_utc_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def read_url(url: str, timeout: int = 45) -> str:
    req = Request(url, headers={"User-Agent": "base-multichain-source-fetcher/1.0"})
    with urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8")


def redact_api_key(url: str) -> str:
    return re.sub(r"(apikey=)[^&]+", r"\1<redacted>", url)


def normalize_evm_address(addr: str) -> str:
    return addr.lower()


def is_valid_evm_address(value: str | None) -> bool:
    return bool(value and EVM_ADDRESS_RE.match(value))


def is_zero_address(value: str | None) -> bool:
    if not value:
        return True
    return value.lower() == "0x" + ("0" * 40)


def parse_abi(raw_abi: str) -> Any | None:
    raw = (raw_abi or "").strip()
    if not raw or raw.lower().startswith("contract source code not verified"):
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def parse_source_map(raw_source: str) -> dict[str, str]:
    source = raw_source or ""
    stripped = source.strip()
    if not stripped:
        return {}

    parsed: Any | None = None
    candidates = [stripped]
    if stripped.startswith("{{") and stripped.endswith("}}") and len(stripped) > 2:
        candidates.append(stripped[1:-1])

    for candidate in candidates:
        try:
            parsed = json.loads(candidate)
            break
        except json.JSONDecodeError:
            continue

    if isinstance(parsed, dict):
        if "sources" in parsed and isinstance(parsed["sources"], dict):
            src_entries = parsed["sources"]
        else:
            src_entries = parsed

        files: dict[str, str] = {}
        for path, val in src_entries.items():
            if isinstance(val, dict):
                content = val.get("content")
            elif isinstance(val, str):
                content = val
            else:
                content = None
            if isinstance(content, str):
                files[str(path)] = content

        if files:
            return files

    return {"Contract.sol": source}


def safe_write_text(base: Path, relative_path: str, content: str) -> Path:
    rel = relative_path.replace("\\", "/").lstrip("/")
    target = (base / rel).resolve()
    base_resolved = base.resolve()
    if not str(target).startswith(str(base_resolved)):
        raise RuntimeError(f"Unsafe source path from explorer: {relative_path}")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    return target


def decode_storage_address(word_hex: str) -> str | None:
    if not isinstance(word_hex, str):
        return None
    value = word_hex.strip().lower()
    if not value.startswith("0x"):
        return None
    body = value[2:]
    if not body:
        return None
    if len(body) < 40:
        body = body.zfill(40)
    if len(body) > 40:
        body = body[-40:]
    addr = f"0x{body}"
    if not is_valid_evm_address(addr) or is_zero_address(addr):
        return None
    return normalize_evm_address(addr)


def etherscan_v2_get_source(api_key: str, chainid: str, address: str) -> dict[str, Any]:
    params = {
        "chainid": chainid,
        "module": "contract",
        "action": "getsourcecode",
        "address": address,
        "apikey": api_key,
    }
    url = f"{ETHERSCAN_V2_API}?{urlencode(params)}"
    payload = read_url(url)
    data = json.loads(payload)

    status = str(data.get("status", ""))
    message = str(data.get("message", ""))
    result = data.get("result")

    if isinstance(result, list) and result and isinstance(result[0], dict):
        entry = result[0]
    else:
        # Normalize unexpected responses into an empty entry.
        entry = {
            "SourceCode": "",
            "ABI": "",
            "ContractName": "",
            "CompilerVersion": "",
            "OptimizationUsed": "",
            "Runs": "",
            "EVMVersion": "",
            "LicenseType": "",
            "Proxy": "",
            "Implementation": "",
        }

    return {
        "status": status,
        "message": message,
        "entry": entry,
        "api_url": redact_api_key(url),
        "raw_result_type": type(result).__name__,
    }


def etherscan_v2_get_storage(api_key: str, chainid: str, address: str, position: str) -> str | None:
    params = {
        "chainid": chainid,
        "module": "proxy",
        "action": "eth_getStorageAt",
        "address": address,
        "position": position,
        "tag": "latest",
        "apikey": api_key,
    }
    url = f"{ETHERSCAN_V2_API}?{urlencode(params)}"
    payload = read_url(url)
    data = json.loads(payload)
    result = data.get("result")
    if isinstance(result, str):
        return result
    return None


def zksync_get_source(api_url: str, address: str) -> dict[str, Any]:
    params = {
        "module": "contract",
        "action": "getsourcecode",
        "address": address,
    }
    url = f"{api_url}?{urlencode(params)}"
    payload = read_url(url)
    data = json.loads(payload)

    status = str(data.get("status", ""))
    message = str(data.get("message", ""))
    result = data.get("result")

    if isinstance(result, list) and result and isinstance(result[0], dict):
        entry = result[0]
    else:
        entry = {
            "SourceCode": "",
            "ABI": "",
            "ContractName": "",
            "CompilerVersion": "",
            "OptimizationUsed": "",
            "Runs": "",
            "EVMVersion": "",
            "LicenseType": "",
            "Proxy": "",
            "Implementation": "",
        }

    return {
        "status": status,
        "message": message,
        "entry": entry,
        "api_url": url,
        "raw_result_type": type(result).__name__,
    }


def fetch_source_for_chain(chain: str, address: str, api_key: str) -> dict[str, Any]:
    cfg = CHAIN_CONFIG[chain]
    kind = cfg["kind"]

    if kind == "etherscan_v2":
        return etherscan_v2_get_source(api_key, cfg["chainid"], address)
    if kind == "zksync_explorer":
        return zksync_get_source(cfg["api_url"], address)

    raise RuntimeError(f"Unsupported chain kind: {kind}")


def fetch_storage_for_chain(chain: str, address: str, api_key: str, position: str) -> str | None:
    cfg = CHAIN_CONFIG[chain]
    kind = cfg["kind"]
    if kind == "etherscan_v2":
        return etherscan_v2_get_storage(api_key, cfg["chainid"], address, position)
    # zkSync explorer API does not expose eth_getStorageAt via this endpoint.
    return None


def write_evm_contract_artifacts(
    out_root: Path,
    chain: str,
    address: str,
    manifest_labels: list[str],
    fetch_info: dict[str, Any],
    implementation_override: str | None = None,
    implementation_source: str | None = None,
) -> dict[str, Any]:
    address_norm = normalize_evm_address(address)
    entry = fetch_info["entry"]

    contract_dir = out_root / "contracts" / chain / address_norm
    contract_dir_resolved = contract_dir.resolve()
    source_dir = contract_dir / "source"
    source_dir.mkdir(parents=True, exist_ok=True)

    raw_source = str(entry.get("SourceCode", ""))
    contract_name = str(entry.get("ContractName", "")).strip() or "UnknownContract"

    source_files = parse_source_map(raw_source)
    wrote_source_files: list[str] = []

    if source_files:
        if len(source_files) == 1 and "Contract.sol" in source_files:
            file_name = f"{contract_name}.sol"
            written = safe_write_text(source_dir, file_name, source_files["Contract.sol"])
            wrote_source_files.append(str(written.relative_to(contract_dir_resolved)))
        else:
            for rel_path, content in source_files.items():
                written = safe_write_text(source_dir, rel_path, content)
                wrote_source_files.append(str(written.relative_to(contract_dir_resolved)))

    abi = parse_abi(str(entry.get("ABI", "")))
    abi_path = None
    if abi is not None:
        abi_path = contract_dir / "abi.json"
        abi_path.write_text(json.dumps(abi, indent=2), encoding="utf-8")

    proxy_flag = str(entry.get("Proxy", "")).strip()
    implementation_raw = str(entry.get("Implementation", "")).strip()
    implementation = implementation_override or implementation_raw

    if is_valid_evm_address(implementation):
        implementation = normalize_evm_address(implementation)
    else:
        implementation = None

    metadata = {
        "chain": chain,
        "address": address_norm,
        "labels_from_input": manifest_labels,
        "contract_name": contract_name,
        "compiler_version": entry.get("CompilerVersion"),
        "optimization_used": entry.get("OptimizationUsed"),
        "runs": entry.get("Runs"),
        "evm_version": entry.get("EVMVersion"),
        "license_type": entry.get("LicenseType"),
        "proxy": proxy_flag,
        "implementation": implementation,
        "implementation_source": implementation_source if implementation else None,
        "source_verified": bool(raw_source.strip()),
        "source_file_count": len(wrote_source_files),
        "api_status": fetch_info.get("status"),
        "api_message": fetch_info.get("message"),
        "api_url": fetch_info.get("api_url"),
        "raw_result_type": fetch_info.get("raw_result_type"),
        "fetched_at": now_utc_iso(),
    }

    (contract_dir / "metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    if raw_source.strip() and not wrote_source_files:
        raw_path = contract_dir / "source" / "raw_source.txt"
        raw_path.write_text(raw_source, encoding="utf-8")
        wrote_source_files.append(str(raw_path.resolve().relative_to(contract_dir_resolved)))

    return {
        "chain": chain,
        "address": address_norm,
        "labels_from_input": manifest_labels,
        "contract_name": contract_name,
        "proxy": proxy_flag,
        "implementation": implementation,
        "implementation_source": implementation_source if implementation else None,
        "source_verified": bool(raw_source.strip()),
        "source_file_count": len(wrote_source_files),
        "metadata_path": str((contract_dir / "metadata.json").relative_to(out_root)),
        "abi_path": str(abi_path.relative_to(out_root)) if abi_path else None,
    }


def write_non_evm_artifact(out_root: Path, chain: str, address: str, labels: list[str]) -> dict[str, Any]:
    item_dir = out_root / "contracts" / chain / address
    item_dir.mkdir(parents=True, exist_ok=True)
    metadata = {
        "chain": chain,
        "address": address,
        "labels_from_input": labels,
        "source_verified": False,
        "note": "Non-EVM chain entry; explorer source fetch not supported by this fetcher",
        "fetched_at": now_utc_iso(),
    }
    (item_dir / "metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    return {
        "chain": chain,
        "address": address,
        "labels_from_input": labels,
        "source_verified": False,
        "metadata_path": str((item_dir / "metadata.json").relative_to(out_root)),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", default="data/input_manifest.json")
    parser.add_argument("--out-dir", default="data")
    parser.add_argument("--sleep-seconds", type=float, default=0.2)
    args = parser.parse_args()

    manifest_path = Path(args.manifest)
    manifest_data = json.loads(manifest_path.read_text(encoding="utf-8"))
    entries = manifest_data.get("entries", [])
    if not isinstance(entries, list) or not entries:
        raise RuntimeError("Manifest has no entries")

    api_key = os.environ.get("ETHERSCAN_API_KEY", "").strip()

    out_root = Path(args.out_dir)
    out_root.mkdir(parents=True, exist_ok=True)

    labels_map: dict[tuple[str, str], list[str]] = {}
    queue: deque[tuple[str, str]] = deque()

    for item in entries:
        chain = str(item.get("chain", "")).strip()
        address = str(item.get("address", "")).strip()
        labels = [str(x) for x in item.get("labels", []) if isinstance(x, str)]
        if not chain or not address:
            continue

        if chain == "solana":
            labels_map[(chain, address)] = labels
            queue.append((chain, address))
            continue

        if not is_valid_evm_address(address):
            continue

        addr_norm = normalize_evm_address(address)
        labels_map[(chain, addr_norm)] = labels
        queue.append((chain, addr_norm))

    seen: set[tuple[str, str]] = set()
    fetched: dict[tuple[str, str], dict[str, Any]] = {}
    proxy_edges: list[dict[str, str]] = []
    unresolved_proxies: list[dict[str, str]] = []
    failures: list[dict[str, str]] = []

    while queue:
        chain, address = queue.popleft()
        key = (chain, address)

        if key in seen:
            continue
        seen.add(key)

        labels = labels_map.get(key, [])

        if chain == "solana":
            fetched[key] = write_non_evm_artifact(out_root, chain, address, labels)
            continue

        if chain not in CHAIN_CONFIG:
            failures.append({"chain": chain, "address": address, "error": "unsupported chain"})
            continue

        if CHAIN_CONFIG[chain]["kind"] != "zksync_explorer" and not api_key:
            raise RuntimeError("ETHERSCAN_API_KEY is required for Etherscan-based chains")

        try:
            fetch_info = fetch_source_for_chain(chain, address, api_key)
            entry = fetch_info["entry"]

            proxy_flag = str(entry.get("Proxy", "")).strip()
            raw_impl = str(entry.get("Implementation", "")).strip()

            resolved_impl: str | None = None
            resolved_source: str | None = None

            if is_valid_evm_address(raw_impl):
                raw_impl_norm = normalize_evm_address(raw_impl)
                if not is_zero_address(raw_impl_norm) and raw_impl_norm != address:
                    resolved_impl = raw_impl_norm
                    resolved_source = "explorer_field"

            if proxy_flag == "1" and not resolved_impl:
                try:
                    storage_word = fetch_storage_for_chain(chain, address, api_key, EIP1967_IMPLEMENTATION_SLOT)
                    slot_impl = decode_storage_address(storage_word or "")
                    if slot_impl and slot_impl != address:
                        resolved_impl = slot_impl
                        resolved_source = "eip1967_slot"
                except Exception:
                    pass

            summary = write_evm_contract_artifacts(
                out_root,
                chain,
                address,
                labels,
                fetch_info,
                implementation_override=resolved_impl,
                implementation_source=resolved_source,
            )
            fetched[key] = summary

            implementation = summary.get("implementation")
            if (
                isinstance(implementation, str)
                and is_valid_evm_address(implementation)
                and normalize_evm_address(implementation) != address
            ):
                impl_norm = normalize_evm_address(implementation)
                proxy_edges.append(
                    {
                        "chain": chain,
                        "proxy": address,
                        "implementation": impl_norm,
                        "resolution": str(summary.get("implementation_source") or ""),
                    }
                )
                impl_key = (chain, impl_norm)
                if impl_key not in labels_map:
                    labels_map[impl_key] = []
                if impl_key not in seen:
                    queue.append(impl_key)
            elif summary.get("proxy") == "1":
                unresolved_proxies.append({"chain": chain, "address": address})

            time.sleep(args.sleep_seconds)

        except Exception as exc:
            failures.append({"chain": chain, "address": address, "error": str(exc)})

    summary = {
        "generated_at": now_utc_iso(),
        "scope": manifest_data.get("scope"),
        "source_manifest": str(manifest_path),
        "initial_manifest_entry_count": len(entries),
        "total_processed_keys": len(seen),
        "total_fetched_entries": len(fetched),
        "proxy_edges": proxy_edges,
        "unresolved_proxies": unresolved_proxies,
        "failures": failures,
        "contracts": [
            fetched[k]
            for k in sorted(
                fetched.keys(),
                key=lambda x: (x[0], x[1]),
            )
        ],
    }

    (out_root / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(f"Initial manifest entries: {len(entries)}")
    print(f"Fetched entries: {len(fetched)}")
    print(f"Proxy edges discovered: {len(proxy_edges)}")
    print(f"Unresolved proxies: {len(unresolved_proxies)}")
    print(f"Failures: {len(failures)}")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise
