-- stg_medicaid_claim_level_detail
-- Claim detail behind CMS-R-144 invoice lines, which a state provides when a manufacturer disputes a line. One row
-- per Medicaid claim, typed. As with the Pilot, the Rx number is standardized without leading zeros next to the value
-- as received (some states pad it). The date of service is kept as sent: whether it is off by a few days is a
-- matching question for the intermediate layer.
-- The manufacturer and the invoice file this detail supports come from the file name (cld_FL_MFR001_12026.csv).
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

select
    state_code,
    regexp_extract(_source_file, 'MFR[0-9]{3}', 0)                   as manufacturer_code,
    concat('r144_', regexp_extract(_source_file, 'cld_(.*)\\.csv', 1), '.txt')
                                                                     as invoice_file,
    record_id,
    case record_id when 'FFSU' then 'fee for service' when 'MCOU' then 'managed care' end
                                                                     as utilization_type,
    period_covered,
    ndc11,
    rx_number,
    nullif(regexp_replace(rx_number, '^0+', ''), '')                 as rx_number_normalized,
    try_cast(fill_number as int)                                     as fill_number,
    try_cast(date_of_service as date)                                as date_of_service,
    try_cast(date_paid as date)                                      as date_paid,
    service_provider_npi,
    prescriber_npi,
    try_cast(units as decimal(14, 3))                                as units,
    try_cast(medicaid_amount_reimbursed as decimal(16, 2))           as medicaid_amount_reimbursed,
    _source_file,
    _ingested_at
from {{ source('raw', 'state_claim_level_detail') }}
