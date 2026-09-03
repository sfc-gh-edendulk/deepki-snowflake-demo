"""Data engineering demo — pure Python transformation, deployed as a stored procedure.

Elizabeth's answer to "our teams are Python-only, some have no SQL at all":
"tout peut etre fait en Python pur." This registers DE_BUILD_ASSET_HARMONISED()
as a permanent Snowflake stored procedure written entirely in Snowpark. No SQL
string is built anywhere in this file — the DataFrame API compiles to SQL, but
nobody writing this procedure had to write it by hand.

It does the same harmonisation job as 03's Dynamic Table, deliberately, so the
two can be compared side by side: one team can own the SQL-first Dynamic Table
path, another can own this Python-first stored procedure path, against the same
underlying data, with the same governance.

Run: .venv/bin/python data_engineering/04_transform_snowpark_procedure.py
"""
import tomllib
from pathlib import Path

from snowflake.snowpark import Session
from snowflake.snowpark import functions as F
from snowflake.snowpark.types import StringType


def build_asset_harmonised(session: Session) -> str:
    """The procedure body. Runs inside Snowflake once deployed; also callable
    directly for local testing before registration."""
    mongo = session.table("DE_STG_ASSET_FROM_MONGO").select(
        F.col("DOCUMENT_ID").alias("SOURCE_REF"),
        F.lit("mongo").alias("SOURCE_SYSTEM"),
        F.col("CLIENT_ID"),
        F.col("ASSET_COUNTRY"),
        F.col("ASSET_CITY"),
        F.col("ASSET_SECTOR"),
        F.col("FLOOR_AREA_M2"),
        F.col("HEATING_SYSTEM"),
        F.col("EPC_RATING"),
    )
    parquet = session.table("DE_RAW_ASSET_PARQUET").select(
        F.col("ASSET_REF").alias("SOURCE_REF"),
        F.lit("parquet_s3").alias("SOURCE_SYSTEM"),
        F.col("CLIENT_REF").alias("CLIENT_ID"),
        F.col("COUNTRY").alias("ASSET_COUNTRY"),
        F.col("CITY").alias("ASSET_CITY"),
        F.col("SECTOR").alias("ASSET_SECTOR"),
        F.col("FLOOR_AREA_SQM").alias("FLOOR_AREA_M2"),
        F.col("HEATING_SYSTEM"),
        F.col("EPC_RATING"),
    )
    combined = mongo.union_all(parquet)

    combined.write.save_as_table("DE_ASSET_HARMONISED_PY", mode="overwrite")

    counts = (
        combined.group_by("SOURCE_SYSTEM")
        .agg(F.count("*").alias("ASSET_COUNT"))
        .collect()
    )
    return "; ".join(f"{r['SOURCE_SYSTEM']}: {r['ASSET_COUNT']}" for r in counts)


def main() -> None:
    # Reads your default connection from ~/.snowflake/connections.toml. Set
    # SNOWFLAKE_CONNECTION_NAME to pick a specific one instead of the default.
    import os
    conf = tomllib.loads((Path.home() / ".snowflake" / "connections.toml").read_text())
    conn_name = os.environ.get("SNOWFLAKE_CONNECTION_NAME") or conf.get("default_connection_name")
    if not conn_name:
        raise SystemExit("Set SNOWFLAKE_CONNECTION_NAME or a default_connection_name in connections.toml")
    c = conf[conn_name]
    session = Session.builder.configs({
        "account": c["account"], "user": c["user"], "password": c["password"],
        "role": c.get("role"), "warehouse": "COMPUTE_WH",
        "database": "CUSTOM_DEMOS", "schema": "DEEPKI",
    }).create()

    # Local sanity call before registering, so a bug in the logic doesn't get
    # deployed and only discovered when someone calls it from SQL.
    result = build_asset_harmonised(session)
    print("Local dry run:", result)

    session.sproc.register(
        func=build_asset_harmonised,
        name="DE_BUILD_ASSET_HARMONISED",
        return_type=StringType(),
        input_types=[],
        packages=["snowflake-snowpark-python"],
        is_permanent=True,
        stage_location="@CUSTOM_DEMOS.DEEPKI.DE_PROC_STAGE",
        replace=True,
        comment=(
            "Pure-Python harmonisation of the Mongo and Parquet asset sources. "
            "Deployed for teams who write Python and no SQL, per the meeting."
        ),
    )
    print("Registered DE_BUILD_ASSET_HARMONISED() as a permanent procedure.")

    called = session.sql("CALL DE_BUILD_ASSET_HARMONISED()").collect()
    print("CALL DE_BUILD_ASSET_HARMONISED() ->", called[0][0])

    row_count = session.table("DE_ASSET_HARMONISED_PY").count()
    print(f"DE_ASSET_HARMONISED_PY row count: {row_count}")
    assert row_count == 100, f"expected 100 rows (40 mongo + 60 parquet), got {row_count}"

    session.close()
    print("\nSTORED PROCEDURE DEPLOYED AND VERIFIED")


if __name__ == "__main__":
    main()
