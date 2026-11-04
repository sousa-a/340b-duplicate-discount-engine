# 340B Duplicate Discount Engine

This is a claim-level detection of Maximum Fair Price (MFP)/340B and Medicaid/340B duplicate discounts and same-fill diversion, reconciled against electronic data interchange (EDI) purchase data project. It employs Databricks, PySpark and dbt (data build tool), on synthetic data. 340B is the drug discount program created by section 340B of the Public Health Service Act.

> **All data in this project is completely synthetic.** No record describes a real covered entity, pharmacy, prescriber, patient or wholesaler. Real public facts (MFP drugs, National Drug Codes (NDCs), published prices, state policies, Pilot rules) enter only as sourced parameters and seeds. See [SYNTHETIC_DATA_NOTICE.md](SYNTHETIC_DATA_NOTICE.md).

## Why this project exists

Sun, Sarraille, Gambino and Martin (IQVIA, October 2026) sized MFP/340B duplicate discounts in aggregate using proprietary national data, estimating $6.1B to $9.3B for 2027 alone depending on the price period. This project builds on that work at a different level. It shows, on synthetic data, how individual duplicates are detected, reconciled against purchase records and evidenced at claim level. It does not estimate national totals, and its figures are not comparable to aggregate industry estimates.

Since the data used in this project is synthetic, every duplicate is planted, so each detection path is scored against known ground truth. Martin and Illich (IQVIA, 2022) note that no accessible data confirms which 340B-eligible claims were actually converted, which is why observational estimates cannot be checked this way.

The project takes no position in the policy debate over 340B. It shows how duplicates are detected and documented, not who is responsible for them. See [SYNTHETIC_DATA_NOTICE.md](SYNTHETIC_DATA_NOTICE.md).

## How it is organized

The `src/generator/` simulates the whole market and knows everything, including the ground truth. Everything from `src/ingestion/` onward sees only what a **manufacturer** could receive like covered entity claim submissions, EDI 844/849/867 files from wholesalers, Medicare Transaction Facilitator (MTF) records and state Medicaid rebate invoices. Ground truth sits in its own schema and is read only by the evaluation step; a test fails the build if any engine model references it.

| Folder | Contents |
|---|---|
| `src/generator/` | synthetic market, X12 writer (X12 is the EDI standard behind the 844, 849 and 867 files), planted scenarios |
| `src/ingestion/` | X12 parser, reference data loaders, NDC normalization |
| `dbt/` | staging, eligibility, reconciliation, three detection paths, evidence table, tests |
| `notebooks/` | pipeline steps and evaluation against ground truth |
| `samples/` | small extracts to inspect without running anything |
| `visuals/` | figures, Tableau workbook, interactive charts |
| `docs/` | design, references, data sources |

## Documentation

- [Synthetic data design](docs/SYNTHETIC_DATA_DESIGN.md)
- [References](docs/REFERENCES.md)
- [Acronyms and terms](docs/ACRONYMS.md)
- [Data sources and downloads](docs/DATA_SOURCES.md)

## How this was built

I built this project with Claude (Anthropic's AI assistant) as a pair programmer and research partner. The scope, the design and every decision behind it are mine, and I went through the primary sources with it (Federal Register notices, guidance from the Centers for Medicare & Medicaid Services (CMS) and the Health Resources and Services Administration (HRSA), the manufacturer plans for the 340B Rebate Model Pilot Program, the wholesaler EDI guides). Facts are checked against those sources and logged in [docs/REFERENCES.md](docs/REFERENCES.md). The tests in `tests/` are how I check that the code does what the docs say.
