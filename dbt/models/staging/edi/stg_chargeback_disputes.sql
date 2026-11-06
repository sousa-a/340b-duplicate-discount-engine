-- stg_chargeback_disputes
-- Chargeback lines the manufacturer disputed, one row per line, with the validation that failed:
--   MISSING_340B_ID                    the 844 line came without a 340B ID
--   UNKNOWN_340B_ID                    the 340B ID is not a covered entity in OPAIS
--   ENTITY_NOT_ACTIVE_ON_INVOICE_DATE  the entity was not participating on the date of the sale
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

select
    sale_line_id,
    debit_memo_number,
    invoice_number,
    ndc11,
    customer_340b_id,
    try_cast(chargeback_amount as decimal(18, 2))                    as chargeback_amount,
    validation                                                       as dispute_reason,
    _source_file,
    _ingested_at
from {{ source('raw', 'chargeback_disputes') }}
