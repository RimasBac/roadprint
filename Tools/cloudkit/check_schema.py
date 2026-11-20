#!/usr/bin/env python3
"""Check that roadprint.ckdb has exactly the CD_ fields Core Data mirrors from TripRecord (ADR 0005 §3, §8).

Mapping used by NSPersistentCloudKitContainer: UUID and String -> STRING, Int -> INT64, Date -> TIMESTAMP,
Data -> BYTES plus a `_ckAsset` ASSET (large values move to an asset). `.allowsCloudEncryption` -> ENCRYPTED.
Run: python3 Tools/cloudkit/check_schema.py [TripRecord.swift] [schema.ckdb]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TYPES = {"UUID": "STRING", "String": "STRING", "Int": "INT64", "Date": "TIMESTAMP", "Data": "BYTES"}


def expected_fields(swift: str) -> dict:
    fields = {"CD_entityName": "STRING"}
    encrypted = False
    for line in swift.splitlines():
        line = line.strip()
        if line.startswith("@Attribute("):
            encrypted = ".allowsCloudEncryption" in line
            continue
        m = re.match(r"var (\w+): (\w+)\??", line)
        if not m:
            continue
        name, swift_type = m.groups()
        if swift_type not in TYPES:
            raise SystemExit(f"TripRecord.{name}: no CloudKit mapping for {swift_type}; extend check_schema.py")
        ck = TYPES[swift_type]
        fields[f"CD_{name}"] = f"ENCRYPTED {ck}" if encrypted else ck
        if swift_type == "Data":
            fields[f"CD_{name}_ckAsset"] = "ASSET"
        encrypted = False
    return fields


def schema_fields(ckdb: str) -> dict:
    m = re.search(r"RECORD TYPE CD_TripRecord \((.*?)\);", ckdb, re.S)
    if not m:
        raise SystemExit("CD_TripRecord missing from schema")
    fields = {}
    for line in m.group(1).splitlines():
        f = re.match(r"\s*(CD_\w+)\s+((?:ENCRYPTED )?[A-Z0-9]+)", line)
        if f:
            fields[f.group(1)] = f.group(2)
    return fields


def main(argv):
    swift = Path(argv[1] if len(argv) > 1 else ROOT / "App/Storage/TripRecord.swift").read_text()
    ckdb = Path(argv[2] if len(argv) > 2 else ROOT / "Tools/cloudkit/roadprint.ckdb").read_text()
    want, have = expected_fields(swift), schema_fields(ckdb)
    problems = [f"missing {k} {v}" for k, v in want.items() if k not in have]
    problems += [f"{k}: schema {have[k]}, model {v}" for k, v in want.items() if k in have and have[k] != v]
    problems += [f"extra {k} (not in TripRecord)" for k in have if k not in want]
    if problems:
        print("CloudKit schema does not match TripRecord:\n  " + "\n  ".join(problems), file=sys.stderr)
        return 1
    print(f"CD_TripRecord matches TripRecord ({len(want)} CD_ fields)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
