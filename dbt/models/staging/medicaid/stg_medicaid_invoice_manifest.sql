-- stg_medicaid_invoice_manifest
-- One row per CMS-R-144 invoice file received: state, manufacturer, quarter, invoice date and number of lines.
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

select
    file                                                             as invoice_file,
    state_code,
    manufacturer_code,
    period_covered,
    try_cast(invoice_date as date)                                   as invoice_date,
    try_cast(lines as int)                                           as lines_declared,
    _source_file,
    _ingested_at
from {{ source('raw', 'state_invoice_manifest') }}
