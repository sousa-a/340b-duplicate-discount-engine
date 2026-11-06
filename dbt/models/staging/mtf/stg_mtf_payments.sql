-- stg_mtf_payments
-- The manufacturer's refund decision and payment for each MTF record, one row per record, typed.
-- Refund method codes (CMS guidance for the Medicare Transaction Facilitator, Table 5):
--   1  Standard Default Refund Amount paid, (WAC - MFP) x quantity
--   4  no refund: the 340B ceiling price is below the MFP, so the claim is not owed an MFP refund (remark N907)
--   8  refund of (ceiling price - MFP) x quantity: the MFP is below the 340B ceiling price (remark N917)
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with source as (

    select * from {{ source('raw', 'mtf_payments') }}

)

select
    mtf_icn,
    transaction_code,
    transaction_code = 'REVERSAL'                                    as is_reversal,
    try_cast(response_date as date)                                  as response_date,
    mtf_pm_facilitation_indicator,
    refund_method_code,
    case refund_method_code
        when '1' then 'SDRA paid'
        when '4' then 'no refund, ceiling below MFP'
        when '8' then 'refund of ceiling minus MFP'
    end                                                              as refund_method,
    try_cast(refund_amount as decimal(18, 2))                        as refund_amount,
    remark_code,
    try_cast(payment_date as date)                                   as payment_date,
    _source_file,
    _ingested_at
from source
