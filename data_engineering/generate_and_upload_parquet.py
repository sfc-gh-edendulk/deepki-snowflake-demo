"""Generate synthetic asset-register Parquet files and upload to S3.

Deepki already has some data in Parquet on S3 (per the meeting notes). This
generates a plausible slice of that — a different subset of assets from the
Mongo-style documents in 01, mirroring how Deepki's real environment has both
sources describing overlapping but not identical parts of the portfolio — and
uploads it to a real bucket, so the Iceberg table in 02 reads real S3 objects.

Run: .venv/bin/python data_engineering/generate_and_upload_parquet.py \
       --bucket <YOUR_S3_BUCKET> --profile <YOUR_AWS_PROFILE>
"""
import argparse
import subprocess
import sys

import pandas as pd

parser = argparse.ArgumentParser()
parser.add_argument("--bucket", required=True, help="Your S3 bucket, e.g. my-company-data-lake")
parser.add_argument("--prefix", default="deepki-demo/asset_parquet", help="Prefix within the bucket")
parser.add_argument("--profile", required=True, help="Your AWS CLI profile name (aws configure sso)")
args = parser.parse_args()

BUCKET = args.bucket
PREFIX = args.prefix
AWS_PROFILE = args.profile

COUNTRIES = ["France", "Germany", "Sweden", "United Kingdom", "Netherlands"]
CITIES = {
    "France": ["Nantes", "Toulouse"], "Germany": ["Stuttgart", "Dusseldorf"],
    "Sweden": ["Malmo", "Uppsala"], "United Kingdom": ["Birmingham", "Glasgow"],
    "Netherlands": ["Eindhoven", "The Hague"],
}
SECTORS = ["Office", "Retail", "Logistics", "Residential"]
HEATING = ["Gas boiler", "Heat pump", "District heating", "Oil boiler"]

rows = []
for n in range(1, 61):
    country = COUNTRIES[n % len(COUNTRIES)]
    rows.append({
        "asset_ref": f"PQ-{n:05d}",
        "client_ref": ["CL001", "CL003", "CL005", "CL007", "CL009"][n % 5],
        "country": country,
        "city": CITIES[country][n % 2],
        "sector": SECTORS[n % len(SECTORS)],
        "floor_area_sqm": round(1800 + (n * 173) % 8200, 2),
        "heating_system": HEATING[n % len(HEATING)],
        "epc_rating": ["A", "B", "C", "D", "E", "F", "G"][n % 7],
        "build_year": 1962 + (n * 11) % 60,
        "source_file_batch": f"2026-06-{(n % 28) + 1:02d}",
    })

df = pd.DataFrame(rows)
local_path = "/tmp/deepki_asset_parquet_batch1.parquet"
df.to_parquet(local_path, engine="pyarrow", index=False)
print(f"Generated {len(df)} rows -> {local_path}")

dest = f"s3://{BUCKET}/{PREFIX}/asset_batch_1.parquet"
result = subprocess.run(
    ["aws", "s3", "cp", local_path, dest, "--profile", AWS_PROFILE],
    capture_output=True, text=True,
)
print(result.stdout)
if result.returncode != 0:
    print(result.stderr, file=sys.stderr)
    sys.exit(1)
print(f"Uploaded to {dest}")
