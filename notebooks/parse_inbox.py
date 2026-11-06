# Databricks notebook source
# /// script
# [tool.databricks.environment]
# environment_version = "6"
# ///
# MAGIC %md
# MAGIC # parse_inbox
# MAGIC
# MAGIC All records read here are **synthetic**. Real public data is used only for sourced parameters and seeds. See SYNTHETIC_DATA_NOTICE.md in the repository.
# MAGIC
# MAGIC This one reads what would be the manufacturer inbox from the Unity Catalog volume `raw.inbox` and writes one Delta table per file type in the `raw` schema. This first section covers the CSV files. The X12 files (844, 849, 867) and the invoices get their own sections later.
# MAGIC
# MAGIC Rules for the RAW layer:
# MAGIC - every value stays _text_, exactly as received (an empty field becomes NULL);
# MAGIC - every row carries the _name of the file_ it came from (`_source_file`) and the _time it was loaded_ (`_ingested_at`);
# MAGIC - typing, NDC normalization and matching happen later, in dbt staging and intermediate models;
# MAGIC - each table is rewritten in full on every run.
# MAGIC
# MAGIC Before writing a table, the notebook checks its structure and halts if something is off:
# MAGIC 1. at least one file matches the pattern;
# MAGIC 2. every file has exactly the expected header, in the expected order;
# MAGIC 3. every row has as many fields as the header;
# MAGIC 4. no header line was read as data;
# MAGIC 5. row count check after the table is written.
# MAGIC
# MAGIC Runs on serverless compute, DataFrame API only.

# COMMAND ----------

dbutils.widgets.text("catalog", "duplicate_discount")
dbutils.widgets.text("inbox_path", "/Volumes/duplicate_discount/raw/inbox")

CATALOG = dbutils.widgets.get("catalog").strip()
INBOX = dbutils.widgets.get("inbox_path").strip().rstrip("/")
RAW_SCHEMA = f"{CATALOG}.raw"

print(f"[parse_inbox] catalog : {CATALOG}")
print(f"[parse_inbox] raw schema : {RAW_SCHEMA}")
print(f"[parse_inbox] inbox volume : {INBOX}")

# COMMAND ----------

# Schema validation and standards enforced! The headers are the file formats as the manufacturer receives them.
# If a file arrives with a different header, the notebook stops instead of guessing.

CSV_SOURCES = {
    "manufacturer_codes": (
        "edi/manufacturer_codes.csv",
        ["manufacturer_code", "manufacturer"],
    ),
    "hrsa_opais_covered_entities": (
        "hrsa_public/opais_covered_entities.csv",
        ["ce_340b_id", "ce_name", "opais_entity_type", "state_code", "participation_start_date", "termination_date"],
    ),
    "hrsa_opais_contract_pharmacies": (
        "hrsa_public/opais_contract_pharmacies.csv",
        ["ce_340b_id", "pharmacy_npi", "pharmacy_name", "pharmacy_state", "contract_start_date", "contract_end_date"],
    ),
    "hrsa_medicaid_exclusion_file": (
        "hrsa_public/medicaid_exclusion_file.csv",
        ["ce_340b_id", "state_code", "billing_npi", "effective_from", "effective_to"],
    ),
    "chargeback_disputes": (
        "manufacturer_chargeback_disputes.csv",
        ["debit_memo_number", "sale_line_id", "invoice_number", "ndc11", "customer_340b_id", "chargeback_amount",
         "validation"],
    ),
    "mtf_claims": (
        "mtf/mtf_claims_*.csv",
        ["record_id", "mtf_icn", "mtf_xref_icn", "process_date", "transaction_code", "medicare_source_of_coverage",
         "date_of_service", "service_provider_id_qualifier", "service_provider_id", "rx_number", "prescriber_id",
         "prescriber_id_qualifier", "fill_number", "ndc11", "quantity_dispensed", "days_supply", "indicator_340b",
         "contract_number", "wac_per_unit", "mfp_per_unit", "sdra"],
    ),
    "mtf_payments": (
        "mtf/mtf_payments_*.csv",
        ["mtf_icn", "transaction_code", "response_date", "mtf_pm_facilitation_indicator", "refund_method_code",
         "refund_amount", "remark_code", "payment_date"],
    ),
    "pilot_submissions": (
        "pilot/pilot_submissions_*.csv",
        ["submission_id", "channel", "submission_date", "ce_340b_id", "date_of_service", "date_prescribed",
         "rx_number", "fill_number", "ndc11", "quantity", "days_supply", "prescriber_npi", "service_provider_npi",
         "rx_bin", "rx_pcn"],
    ),
    "pilot_rebate_status": (
        "pilot/pilot_rebate_status_*.csv",
        ["submission_id", "submission_date", "ce_340b_id", "ndc11", "date_of_service", "quantity", "unit_wac",
         "unit_340b_price", "rebate_amount", "status", "decision_date", "denial_reason", "payment_date"],
    ),
    "pilot_ceiling_prices": (
        "pilot/pilot_ceiling_prices_*.csv",
        ["ndc11", "year_quarter", "package_days", "wac_per_package", "ceiling_price_per_package"],
    ),
    "state_invoice_manifest": (
        "state_invoices/invoice_manifest.csv",
        ["file", "state_code", "manufacturer_code", "period_covered", "invoice_date", "lines"],
    ),
    # Claim-level detail is loaded whole
    "state_claim_level_detail": (
        "state_claim_level_detail/cld_*.csv",
        ["state_code", "record_id", "period_covered", "ndc11", "rx_number", "fill_number", "date_of_service",
         "date_paid", "service_provider_npi", "prescriber_npi", "units", "medicaid_amount_reimbursed"],
    ),
}

print(f"[parse_inbox] CSV file types to load: {len(CSV_SOURCES)}")


# COMMAND ----------

from pyspark.sql import functions as F

# Byte Order Mark (BOM) mitigation
# The generator writes CSV in UTF-8 with a byte order mark (utf-8-sig), so the first header field of every file
# starts with U+FEFF. Since Spark keeps that character in the column name; it is stripped here.
BOM = "\ufeff"


class InboxStructureError(Exception):
    """Raised when an inbox file does not have the structure the engine expects."""


def read_inbox_csv(pattern: str, expected: list):
    """Read every file matching the pattern as text. Check its structure and add the lineage columns."""
    path = f"{INBOX}/{pattern}"
    reader = (
        spark.read.format("csv")
        .option("header", "true")
        .option("inferSchema", "false")      # everything stays text in the raw layer
        .option("encoding", "UTF-8")
        .option("mode", "FAILFAST")          # check 3: a row with too few or too many fields raises
        .option("enforceSchema", "false")    # check 2: Spark compares the header of every file, not only the first
    )
    try:
        df = reader.load(path)
    except Exception as exc:
        # check 1 - no file (PATH_NOT_FOUND)
        raise InboxStructureError(f"cannot read {path}: {exc}") from exc

    found = [c.replace(BOM, "") for c in df.columns] # BOM stripping
    if found != expected:
        missing = [c for c in expected if c not in found]
        extra = [c for c in found if c not in expected]
        raise InboxStructureError(
            f">>>{pattern}: header differs from the expected format! missing {missing}, unexpected {extra}, "
            f"found order {found}"
        )

    # Rename the BOM column and add lineage columns.
    return df.select(
        *[F.col(f"`{raw}`").alias(clean) for raw, clean in zip(df.columns, found)],
        F.col("_metadata.file_name").alias("_source_file"),
        F.current_timestamp().alias("_ingested_at"),
    )


def check_and_write(table: str, df, expected: list) -> dict:
    """Run checks 4 and 5 around the write and return the counts for the summary."""
    first = expected[0]
    try:
        stats = df.agg(
            F.count(F.lit(1)).alias("rows"),
            F.countDistinct("_source_file").alias("files"),
            F.sum(F.when(F.col(first) == F.lit(first), 1).otherwise(0)).alias("header_rows"),
            F.max(F.length(F.concat_ws(",", *[F.col(c) for c in expected]))).alias("widest_row"),
        ).collect()[0]
    except Exception as exc:
        lines = str(exc).splitlines()
        named = [l for l in lines if "CSV header does not conform" in l or ">>> Malformed CSV record" in l]
        reason = (named[0] if named else lines[0]).strip()[:600]
        raise InboxStructureError(f"{table}: a file does not have the expected structure; Spark says: {reason}") from exc
    rows, files, header_rows = stats["rows"], stats["files"], stats["header_rows"] or 0

    if rows == 0:
        raise InboxStructureError(f"{table}: the files contain a header but no rows")
    if header_rows:
        raise InboxStructureError(f"{table}: {header_rows} header line(s) read as data")

    target = f"{RAW_SCHEMA}.{table}"
    (
        df.write.mode("overwrite")
        .option("overwriteSchema", "true")
        .saveAsTable(target)
    )
    written = spark.table(target).count()
    if written != rows:
        raise InboxStructureError(f"{target}: {rows} rows read but {written} rows in the table after the write")

    print(f"[parse_inbox] {target:<52} {files:>6,} file(s) {rows:>10,} rows {len(expected):>3} columns  structure OK")
    return {"table": target, "files": files, "rows": rows, "columns": len(expected)}

# COMMAND ----------

# Load every CSV file type. One failure stops the run.
summary = []
for table, (pattern, expected) in CSV_SOURCES.items():
    print(f"[parse_inbox] reading {pattern}")
    summary.append(check_and_write(table, read_inbox_csv(pattern, expected), expected))

total_rows = sum(s["rows"] for s in summary)
total_files = sum(s["files"] for s in summary)
print(f"[parse_inbox] CSV done: {len(summary)} tables, {total_files:,} files, {total_rows:,} rows")
display(spark.createDataFrame(summary))

# COMMAND ----------

# MAGIC %md
# MAGIC ## X12 files (844, 849, 867)
# MAGIC
# MAGIC The EDI files arrive in ANSI X12 version 004010.
# MAGIC The interchange is held by a file that has an `ISA` envelope, the functional groups (`GS` ... `GE`), and the transaction sets (`ST` ... `SE`) that carry the business data. The interchange closes with `IEA`.
# MAGIC
# MAGIC The raw layer keeps X12 as received, one row per segment, and does not interpret the loops yet (which `SII` line belongs to which pharmacy, which `N9` holds the invoice). It groups which line belongs to which pharmacy, which `N9` holds the invoice etc. Then, all that grouped business logic goes to dbt staging, where it is visible and tested.
# MAGIC
# MAGIC What this section adds to each segment is only its address in the file including position, interchange, group and transaction control numbers.
# MAGIC
# MAGIC The `elements` is an array whose position 0 is the segment ID, **so position 1 is element 01 of the X12 standard** (`SII` element 02, the NDC, is `elements[2]` in Spark SQL).
# MAGIC
# MAGIC Envelope checks, all from the X12 envelope rules. Any failure stops the run before the table is written:
# MAGIC 1. delimiters read from the `ISA` segment are the expected ones (element `|`, component `>`, segment `~`), so the file can be split safely;
# MAGIC 2. the `ISA` segment has its fixed length of 105 characters, and the file has as many `ISA` as `IEA`;
# MAGIC 3. every `ST01` is the transaction set of the folder (844, 849 or 867) and every `GS01` the matching functional identifier (`CF` for 844 and 849, `PT` for 867);
# MAGIC 4. every `SE01` equals the number of segments from `ST` to `SE` inclusive, and `SE02` equals `ST02`;
# MAGIC 5. every `GE01` equals the number of transaction sets in its group, and `GE02` equals `GS06`;
# MAGIC 6. every `IEA01` equals the number of groups in its interchange, and `IEA02` equals `ISA13`;
# MAGIC 7. the row count of the final table equals the segments checked.
# MAGIC
# MAGIC Unlike the CSV section, the checks run after a first write, on a holding table, because serverless compute cannot cache a DataFrame and re-reading every file for each check would be slow. The holding table only replaces the real one when every check passes.

# COMMAND ----------

from pyspark.sql import Window

# Folder -> (target table, expected GS01 functional identifier).
X12_SOURCES = {
    "844": ("edi_844_segments", "CF"),
    "849": ("edi_849_segments", "CF"),
    "867": ("edi_867_segments", "PT"),
}
# Delimiters the engine expects. In X12 they are declared by the ISA segment itself: the element separator is the
# 4th character of the file, the component separator ISA16 (character 105) and the segment terminator the
# character right after ISA16 (character 106). They are read per file and compared with these.
ELEMENT_SEP, COMPONENT_SEP, SEGMENT_TERM = "|", ">", "~"
ISA_LENGTH = 105  # ISA without its terminator: fixed width in X12

ENVELOPE = ["ISA", "GS", "GE", "IEA"]


def read_x12_segments(kind: str):
    """One row per segment for every file of one X12 folder, with its envelope address."""
    path = f"{INBOX}/edi/{kind}/*.x12"
    try:
        files = (
            spark.read.format("text")
            .option("wholetext", "true")      # one row per file: X12 has no line structure of its own
            .load(path)
            .select(F.col("value").alias("text"), F.col("_metadata.file_name").alias("_source_file"))
        )
    except Exception as exc:
        raise InboxStructureError(f"cannot read {path}: {exc}") from exc

    # Some senders break lines after each segment terminator; line breaks are not part of X12 content.
    files = files.withColumn("text", F.regexp_replace("text", "[\\r\\n]", ""))

    # Check 1 - delimiters declared in each file's ISA.
    bad_delims = files.where(
        (F.substring("text", 4, 1) != ELEMENT_SEP)
        | (F.substring("text", 105, 1) != COMPONENT_SEP)
        | (F.substring("text", 106, 1) != SEGMENT_TERM)
        | (F.substring("text", 1, 3) != "ISA")
    ).select("_source_file").limit(5).collect()
    if bad_delims:
        raise InboxStructureError(
            f"edi/{kind}: files that do not start with an ISA using delimiters "
            f"{ELEMENT_SEP} {COMPONENT_SEP} {SEGMENT_TERM}: {[r['_source_file'] for r in bad_delims]}"
        )

    segs = (
        files.select("_source_file", F.posexplode(F.split("text", "\\" + SEGMENT_TERM)).alias("segment_position", "segment_text"))
        .where(F.col("segment_text") != "")    # the file ends with a terminator, which leaves one empty piece
        .withColumn("elements", F.split("segment_text", "\\" + ELEMENT_SEP))
        .withColumn("segment_id", F.col("elements")[0])
    )

    # Envelope address of each segment: the control number of the ISA, GS and ST it sits in, carried forward in
    # file order. Envelope segments themselves get no transaction number, ISA and IEA no group number.
    w = Window.partitionBy("_source_file").orderBy("segment_position").rowsBetween(Window.unboundedPreceding, 0)
    sid = F.col("segment_id")
    segs = (
        segs.withColumn("isa_control_number", F.last(F.when(sid == "ISA", F.col("elements")[13]), ignorenulls=True).over(w))
        .withColumn("gs_control_number", F.when(~sid.isin("ISA", "IEA"),
                    F.last(F.when(sid == "GS", F.col("elements")[6]), ignorenulls=True).over(w)))
        .withColumn("st_control_number", F.when(~sid.isin(*ENVELOPE),
                    F.last(F.when(sid == "ST", F.col("elements")[2]), ignorenulls=True).over(w)))
    )
    return segs.select(
        F.lit(kind).alias("x12_type"),
        "_source_file", "segment_position", "isa_control_number", "gs_control_number", "st_control_number",
        "segment_id", "elements", "segment_text",
        F.current_timestamp().alias("_ingested_at"),
    )


def check_x12_envelopes(kind: str, gs01: str, segs) -> dict:
    """Checks 2 to 6. Returns counts for the summary; raises on the first rule broken."""
    e = F.col("elements")
    sid = F.col("segment_id")
    problems = {}

    # Check 2 - ISA length and ISA/IEA balance per file.
    per_file = segs.groupBy("_source_file").agg(
        F.sum(F.when(sid == "ISA", 1).otherwise(0)).alias("isa"),
        F.sum(F.when(sid == "IEA", 1).otherwise(0)).alias("iea"),
        F.max(F.when(sid == "ISA", F.length("segment_text"))).alias("isa_len"),
    )
    problems["ISA/IEA count or ISA length"] = per_file.where(
        (F.col("isa") != F.col("iea")) | (F.col("isa") < 1) | (F.col("isa_len") != ISA_LENGTH))

    # Check 3 - transaction set and functional identifier.
    problems[f"ST01 not {kind}"] = segs.where((sid == "ST") & (e[1] != kind))
    problems[f"GS01 not {gs01}"] = segs.where((sid == "GS") & (e[1] != gs01))

    # Check 4 - SE01 counts the segments from ST to SE inclusive; SE02 repeats ST02.
    txn = segs.where(F.col("st_control_number").isNotNull()).groupBy("_source_file", "st_control_number").agg(
        F.count(F.lit(1)).alias("segments"),
        F.max(F.when(sid == "SE", e[1].cast("int"))).alias("se01"),
        F.max(F.when(sid == "SE", e[2])).alias("se02"),
        F.sum(F.when(sid == "ST", 1).otherwise(0)).alias("st"),
    )
    problems["SE01 count or SE02 control number"] = txn.where(
        (F.col("se01").isNull()) | (F.col("se01") != F.col("segments"))
        | (F.col("se02") != F.col("st_control_number")) | (F.col("st") != 1))

    # Check 5 - GE01 counts the transaction sets of its group; GE02 repeats GS06.
    grp = segs.where(F.col("gs_control_number").isNotNull()).groupBy("_source_file", "gs_control_number").agg(
        F.sum(F.when(sid == "ST", 1).otherwise(0)).alias("st"),
        F.max(F.when(sid == "GE", e[1].cast("int"))).alias("ge01"),
        F.max(F.when(sid == "GE", e[2])).alias("ge02"),
    )
    problems["GE01 count or GE02 control number"] = grp.where(
        (F.col("ge01").isNull()) | (F.col("ge01") != F.col("st")) | (F.col("ge02") != F.col("gs_control_number")))

    # Check 6 - IEA01 counts the groups of its interchange; IEA02 repeats ISA13.
    ich = segs.groupBy("_source_file", "isa_control_number").agg(
        F.sum(F.when(sid == "GS", 1).otherwise(0)).alias("gs"),
        F.max(F.when(sid == "IEA", e[1].cast("int"))).alias("iea01"),
        F.max(F.when(sid == "IEA", e[2])).alias("iea02"),
    )
    problems["IEA01 count or IEA02 control number"] = ich.where(
        (F.col("iea01").isNull()) | (F.col("iea01") != F.col("gs")) | (F.col("iea02") != F.col("isa_control_number")))

    for rule, bad in problems.items():
        sample = bad.select("_source_file").limit(5).collect()
        if sample:
            raise InboxStructureError(f"edi/{kind}: {rule} broken in {[r['_source_file'] for r in sample]}")

    counts = segs.agg(
        F.countDistinct("_source_file").alias("files"),
        F.count(F.lit(1)).alias("segments"),
        F.sum(F.when(sid == "ST", 1).otherwise(0)).alias("transactions"),
    ).collect()[0]
    print(f"[parse_inbox] edi/{kind}: envelopes OK ({counts['files']:,} files, {counts['transactions']:,} transaction sets, "
          f"{counts['segments']:,} segments)")
    return counts.asDict()

# COMMAND ----------

# Parse, check and write each X12 folder.
# The checks read the segments six times. Serverless compute does not support df.cache(), and re-reading thousands
# of files for every check would be slow, so the segments are first written once to a holding table
# (<table>__incoming) and the checks run on that Delta table. Only if every check passes does the holding table
# replace the real one. If a check fails, the holding table is dropped and the previous raw table stays as it was.
for kind, (table, gs01) in X12_SOURCES.items():
    print(f"[parse_inbox] reading edi/{kind}/*.x12")
    target = f"{RAW_SCHEMA}.{table}"
    incoming = f"{target}__incoming"
    read_x12_segments(kind).write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(incoming)
    try:
        counts = check_x12_envelopes(kind, gs01, spark.table(incoming))
    except Exception:
        spark.sql(f"DROP TABLE IF EXISTS {incoming}")
        print(f"[parse_inbox] {incoming} dropped; {target} left unchanged")
        raise

    spark.sql(f"DROP TABLE IF EXISTS {target}")
    spark.sql(f"ALTER TABLE {incoming} RENAME TO {target}")
    written = spark.table(target).count()
    if written != counts["segments"]:
        raise InboxStructureError(f"{target}: {counts['segments']} segments checked but {written} rows after the rename")

    # columns - : the 8 segment columns, leaving out the two lineage columns, as in the CSV summary
    n_columns = len([c for c in spark.table(target).columns if c not in ("_source_file", "_ingested_at")])
    print(f"[parse_inbox] {target:<52} {counts['files']:>6,} file(s) {written:>10,} rows {n_columns:>3} columns  structure OK")
    summary.append({"table": target, "files": counts["files"], "rows": written, "columns": n_columns})

print(f"[parse_inbox] after X12: {len(summary)} tables, {sum(s['rows'] for s in summary):,} rows")
display(spark.createDataFrame(summary))

# COMMAND ----------

# MAGIC %md
# MAGIC ## CMS-R-144 state invoices (fixed width)
# MAGIC
# MAGIC Each state sends one invoice file per manufacturer and quarter. Every line is one record for one NDC, quarter and record type (`FFSU` fee for service, `MCOU` managed care), and every field sits at a fixed position. The fields and their widths follow the CMS-R-144 data definitions of July 2021. That document gives widths but no column positions, so the positions here follow the field order, and a line is 136 characters long. The last field is a one-position filler, which used to hold the correction flag.
# MAGIC
# MAGIC The raw table keeps every field exactly as cut from the line, padding included (amounts zero-padded on the left, the product name space-padded on the right). Trimming and casting to numbers happen in dbt staging.
# MAGIC
# MAGIC Checks, before the final table is replaced:
# MAGIC 1. at least one invoice file exists;
# MAGIC 2. every line is exactly 136 characters;
# MAGIC 3. the record ID is `FFSU` or `MCOU`, and labeler, product, package and period are digits: if a field were cut at the wrong place, these would break first;
# MAGIC 4. every amount field has a decimal point followed by its published number of decimals (URA 6, units 3, money 2), the number of prescriptions is all digits;
# MAGIC 5. the invoice files and the manifest agree: same set of files, and the same number of lines per file (the manifest must have been loaded by the CSV section above);
# MAGIC 6. the row count of the final table equals the lines checked.
# MAGIC
# MAGIC Like the X12 section, the lines are first written to a holding table and checked there.

# COMMAND ----------

# Field name -> width, in the order of the July 2021 data definitions.
R144_FIELDS = [
    ("record_id", 4), ("state_code", 2), ("labeler_code", 5), ("product_code", 4), ("package_size", 2),
    ("period_covered", 5), ("fda_product_name", 10), ("ura", 15), ("units_reimbursed", 16),
    ("rebate_amount_claimed", 16), ("number_of_prescriptions", 8), ("medicaid_amount_reimbursed", 16),
    ("non_medicaid_amount_reimbursed", 16), ("total_amount_reimbursed", 16), ("filler", 1),
]
R144_LINE_LENGTH = sum(w for _, w in R144_FIELDS)   # 136
R144_DECIMALS = {"ura": 6, "units_reimbursed": 3, "rebate_amount_claimed": 2, "medicaid_amount_reimbursed": 2,
                 "non_medicaid_amount_reimbursed": 2, "total_amount_reimbursed": 2}
R144_DIGITS = ["labeler_code", "product_code", "package_size", "period_covered", "number_of_prescriptions"]

# 1-based start of each field, as Spark's substring expects.
R144_START, _pos = {}, 1
for _name, _width in R144_FIELDS:
    R144_START[_name] = _pos
    _pos += _width
print(f"[parse_inbox] CMS-R-144 layout: {len(R144_FIELDS)} fields, line length {R144_LINE_LENGTH}")


def read_r144_lines():
    """One row per invoice line, cut into its fields, with file name and line number."""
    path = f"{INBOX}/state_invoices/r144_*.txt"
    try:
        files = (
            spark.read.format("text")
            .option("wholetext", "true")      # whole file per row, so each line keeps its number in the file
            .load(path)
            .select(F.col("value").alias("text"), F.col("_metadata.file_name").alias("_source_file"))
        )
    except Exception as exc:
        raise InboxStructureError(f"cannot read {path}: {exc}") from exc

    lines = (
        files.select("_source_file",
                     F.posexplode(F.split(F.regexp_replace("text", "\\r", ""), "\\n")).alias("line_index", "line_text"))
        .where(F.col("line_text") != "")      # the file ends with a newline, which leaves one empty piece
        .withColumn("line_number", F.col("line_index") + 1)
    )
    fields = [F.substring("line_text", R144_START[n], w).alias(n) for n, w in R144_FIELDS]
    return lines.select(
        "_source_file", "line_number", F.length("line_text").alias("line_length"), *fields, "line_text",
        F.current_timestamp().alias("_ingested_at"),
    )


def check_r144(lines) -> dict:
    """Checks 2 to 5. Returns counts for the summary; raises on the first rule broken."""
    c = F.col
    problems = {
        f"line length not {R144_LINE_LENGTH}": lines.where(c("line_length") != R144_LINE_LENGTH),
        "record ID not FFSU or MCOU": lines.where(~c("record_id").isin("FFSU", "MCOU")),
        "field not all digits (" + ", ".join(R144_DIGITS) + ")":
            lines.where(F.greatest(*[(~c(n).rlike("^[0-9]+$")).cast("int") for n in R144_DIGITS]) == 1),
        "period not QYYYY": lines.where(~c("period_covered").rlike("^[1-4][0-9]{4}$")),
    }
    for n, d in R144_DECIMALS.items():
        problems[f"{n} not digits with {d} decimals"] = lines.where(~c(n).rlike(f"^[0-9]+\\.[0-9]{{{d}}}$"))

    # Check 5 - the manifest written by the CSV section, against the files actually read.
    manifest = spark.table(f"{RAW_SCHEMA}.state_invoice_manifest").select(
        c("file").alias("_source_file"), c("lines").cast("int").alias("manifest_lines"))
    per_file = lines.groupBy("_source_file").agg(F.count(F.lit(1)).alias("lines_read"))
    problems["file and manifest disagree (missing on one side or different line count)"] = (
        per_file.join(manifest, "_source_file", "full_outer")
        .where(c("lines_read").isNull() | c("manifest_lines").isNull() | (c("lines_read") != c("manifest_lines")))
    )

    for rule, bad in problems.items():
        sample = bad.select("_source_file").limit(5).collect()
        if sample:
            raise InboxStructureError(f"state_invoices: {rule}, in {[r['_source_file'] for r in sample]}")

    counts = lines.agg(F.countDistinct("_source_file").alias("files"), F.count(F.lit(1)).alias("lines")).collect()[0]
    print(f"[parse_inbox] state_invoices: structure OK ({counts['files']:,} files, {counts['lines']:,} lines)")
    return counts.asDict()

# COMMAND ----------

target = f"{RAW_SCHEMA}.state_invoice_lines"
incoming = f"{target}__incoming"
print("[parse_inbox] reading state_invoices/r144_*.txt")
read_r144_lines().write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(incoming)
try:
    counts = check_r144(spark.table(incoming))
except Exception:
    spark.sql(f"DROP TABLE IF EXISTS {incoming}")
    print(f"[parse_inbox] {incoming} dropped; {target} left unchanged")
    raise

spark.sql(f"DROP TABLE IF EXISTS {target}")
spark.sql(f"ALTER TABLE {incoming} RENAME TO {target}")
written = spark.table(target).count()
if written != counts["lines"]:
    raise InboxStructureError(f"{target}: {counts['lines']} lines checked but {written} rows after the rename")

n_columns = len([c for c in spark.table(target).columns if c not in ("_source_file", "_ingested_at")])
print(f"[parse_inbox] {target:<52} {counts['files']:>6,} file(s) {written:>10,} rows {n_columns:>3} columns  structure OK")
summary.append({"table": target, "files": counts["files"], "rows": written, "columns": n_columns})

print(f"[parse_inbox] all done: {len(summary)} tables, {sum(s['files'] for s in summary):,} files, "
      f"{sum(s['rows'] for s in summary):,} rows")
display(spark.createDataFrame(summary))