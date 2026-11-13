# Inbox Extract Samples

**All data in this folder is completely synthetic.** No file describes a real organization, provider, patient or transaction. See [SYNTHETIC_DATA_NOTICE.md](../../SYNTHETIC_DATA_NOTICE.md) for the full notice.

These files are a small extract of the synthetic manufacturer inbox produced by the generator. They show the structure and content of the EDI files (X12 004010 844 chargebacks, 849 chargeback responses, 867 product transfer reports), Pilot rebate submissions and other inbox documents the detection engine ingests, without requiring a full generator run.

Each subfolder contains files for one manufacturer or state. The extract covers a limited set of covered entities, pharmacies and date ranges. It is enough to inspect the file formats and column layouts but is not intended for a standalone engine run.

## Identifier conventions

- Covered entity IDs follow the pattern `SYN-DSH-PA001`, `SYN-FQHC-FL001`, etc.
- Pharmacy IDs follow the pattern `SYN-RX-PA0001`.
- National Provider Identifiers (NPIs) start with 2 and pass the check digit. All real NPIs start with 1.
- Drug Enforcement Administration (DEA) format numbers in the EDI files fail the check digit on purpose.
- Prescription numbers, claim IDs and patient IDs use synthetic prefixes (`SYN-CLM-`, `PT`).

For the full identifier design, see the root [SYNTHETIC_DATA_NOTICE.md](../../SYNTHETIC_DATA_NOTICE.md).
