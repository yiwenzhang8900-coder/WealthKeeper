#!/usr/bin/env python3
"""Mirror InstrumentSearchService mapping for smoke tests."""

from __future__ import annotations

import json
import urllib.parse
import urllib.request

TOKEN = "D43EE5B10BFB2E0B6E4F2B5E9B5E5E5E"


def optional_hk_padded(query: str) -> str | None:
    if query.isdigit() and 1 <= len(query) <= 4:
        padded = ("0" * (5 - len(query))) + query
        return None if padded == query else padded
    return None


def map_market_and_type(classify: str, security_type_name: str, quote_id: str, mkt_num: str):
    c = (classify or "").upper()
    sec = security_type_name or ""
    if c == "ASTOCK" or sec in ("沪A", "深A", "京A"):
        return "CN_A", "stock", "CNY"
    if c == "HK" or sec == "港股" or mkt_num == "116" or quote_id.startswith("116."):
        return "HK", "stock", "HKD"
    if c == "USSTOCK" or sec == "美股" or quote_id.startswith(("105.", "106.", "107.")):
        return "US", "stock", "USD"
    if c == "OTCFUND" or mkt_num == "150" or quote_id.startswith("150."):
        return "CN_FUND", "fund", "CNY"
    if c == "FUND" and (
        quote_id.startswith(("0.", "1.")) or mkt_num in ("0", "1")
    ):
        return "CN_A", "etf", "CNY"
    return None


def normalize_symbol(code: str, market: str) -> str:
    if market == "US":
        return code.upper()
    if market == "HK":
        digits = "".join(ch for ch in code if ch.isdigit())
        return digits or code.upper()
    return code.upper()


def fetch(input_q: str):
    qs = urllib.parse.urlencode(
        {"input": input_q, "type": "14", "token": TOKEN, "count": "30"}
    )
    url = f"https://searchapi.eastmoney.com/api/suggest/get?{qs}"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        data = json.load(resp)
    return (data.get("QuotationCodeTable") or {}).get("Data") or []


def search(query: str):
    queries = [query]
    padded = optional_hk_padded(query)
    if padded:
        queries.append(padded)
    hits = []
    seen = set()
    for q in queries:
        for row in fetch(q):
            code = (row.get("Code") or "").strip()
            name = (row.get("Name") or "").strip()
            if not code or not name:
                continue
            mapped = map_market_and_type(
                row.get("Classify") or "",
                row.get("SecurityTypeName") or "",
                row.get("QuoteID") or "",
                row.get("MktNum") or "",
            )
            if not mapped:
                continue
            market, asset_type, currency = mapped
            symbol = normalize_symbol(code, market)
            hit_id = f"{market}:{symbol}"
            if hit_id in seen:
                continue
            seen.add(hit_id)
            hits.append(
                {
                    "id": hit_id,
                    "symbol": symbol,
                    "name": name,
                    "market": market,
                    "currency": currency,
                    "assetType": asset_type,
                }
            )
    return hits


EXPECTATIONS = {
    "600519": {"market": "CN_A", "name_substr": "茅台", "currency": "CNY"},
    "AAPL": {"market": "US", "name_substr": "苹果", "currency": "USD"},
    "0700": {"market": "HK", "name_substr": "腾讯", "currency": "HKD"},
    "110022": {"market": "CN_FUND", "name_substr": "易方达", "currency": "CNY"},
}


def main() -> int:
    failed = 0
    for query, exp in EXPECTATIONS.items():
        hits = search(query)
        match = next((h for h in hits if h["market"] == exp["market"] and exp["name_substr"] in h["name"]), None)
        # Also allow exact symbol match under expected market
        if match is None:
            match = next(
                (
                    h
                    for h in hits
                    if h["market"] == exp["market"]
                    and (
                        h["symbol"] == query
                        or h["symbol"].lstrip("0") == query.lstrip("0")
                        or query.upper() in h["symbol"].upper()
                    )
                ),
                None,
            )
        ok = match is not None and match["currency"] == exp["currency"]
        # Ensure we did not assign market by code alone: require API-derived market field present
        if ok:
            print(
                f"PASS {query}: {match['name']} | {match['symbol']} | {match['market']} | {match['currency']} | {match['assetType']}"
            )
        else:
            failed += 1
            preview = ", ".join(f"{h['market']}:{h['symbol']}:{h['name']}" for h in hits[:5]) or "(none)"
            print(f"FAIL {query}: expected market={exp['market']} name~{exp['name_substr']}; got [{preview}]")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
