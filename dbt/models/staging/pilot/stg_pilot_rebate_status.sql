-- stg_pilot_rebate_status
-- The manufacturer's decision on each Pilot submission, one row per submission, typed.
-- The file repeats the NDC as the entity submitted it, so it gets the same standardization as the submissions.
-- rebate_amount is quantity x (unit WAC - unit 340B price) on the submitted quantity.
--
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with source as (

    select * from {{ source('raw', 'pilot_rebate_status') }}

),

typed as (

    select
        submission_id,
        regexp_extract(_source_file, 'MFR[0-9]{3}', 0)              as manufacturer_code,
        ce_340b_id,

        try_cast(submission_date as date)                            as submission_date,
        try_cast(date_of_service as date)                            as date_of_service,

        ndc11                                                        as ndc_as_submitted,
        {{ normalize_ndc11('ndc11') }}                               as ndc11,
        try_cast(quantity as decimal(14, 3))                         as quantity,

        try_cast(unit_wac as decimal(18, 6))                         as unit_wac,
        try_cast(unit_340b_price as decimal(18, 6))                  as unit_340b_price,
        try_cast(rebate_amount as decimal(18, 2))                    as rebate_amount,

        -- decision
        status,
        status = 'PAID'                                              as is_paid,
        denial_reason,
        try_cast(decision_date as date)                              as decision_date,
        try_cast(payment_date as date)                               as payment_date,

        _source_file,
        _ingested_at

    from source

)

select * from typed
