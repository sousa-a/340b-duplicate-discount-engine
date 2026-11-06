-- stg_medicaid_invoice_lines
-- CMS-R-144 state Medicaid rebate invoice lines, one row per line, trimmed and typed.
-- The raw table keeps every field padded exactly as cut from the fixed-width line; here the padding goes:
-- numbers are cast (leading zeros disappear), text is trimmed. The three NDC segments (labeler 5, product 4,
-- package 2) are joined into the 11-digit NDC, and the quarter (period covered, QYYYY) gets its first and last day.
-- Rebate claimed = URA x units reimbursed (CMS-R-144 data definitions, July 2021); FFS units count in the quarter
-- the state paid the claim, MCO units in the quarter the drug was dispensed.
-- The state and manufacturer of the invoice come from the file name (r144_FL_MFR001_12026.txt).
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with source as (

    select * from {{ source('raw', 'state_invoice_lines') }}

),

typed as (

    select
        -- line identity: the file and the line number within it
        _source_file,
        line_number,
        regexp_extract(_source_file, 'MFR[0-9]{3}', 0)                    as manufacturer_code,

        trim(record_id)                                                   as record_id,
        case trim(record_id) when 'FFSU' then 'fee for service' when 'MCOU' then 'managed care' end
                                                                          as utilization_type,
        trim(state_code)                                                  as state_code,
        concat(labeler_code, product_code, package_size)                  as ndc11,
        trim(fda_product_name)                                            as fda_product_name,

        trim(period_covered)                                              as period_covered,
        try_cast(substr(period_covered, 1, 1) as int)                     as quarter,
        try_cast(substr(period_covered, 2, 4) as int)                     as year,

        try_cast(ura as decimal(15, 6))                                   as ura,
        try_cast(units_reimbursed as decimal(16, 3))                      as units_reimbursed,
        try_cast(rebate_amount_claimed as decimal(16, 2))                 as rebate_amount_claimed,
        try_cast(number_of_prescriptions as int)                          as number_of_prescriptions,
        try_cast(medicaid_amount_reimbursed as decimal(16, 2))            as medicaid_amount_reimbursed,
        try_cast(non_medicaid_amount_reimbursed as decimal(16, 2))        as non_medicaid_amount_reimbursed,
        try_cast(total_amount_reimbursed as decimal(16, 2))               as total_amount_reimbursed,

        _ingested_at

    from source

)

select
    *,
    -- guarded: with ANSI SQL on, make_date fails the query on an impossible quarter
    case when quarter between 1 and 4 then make_date(year, (quarter - 1) * 3 + 1, 1) end
                                                                          as quarter_start_date,
    case when quarter between 1 and 4 then last_day(make_date(year, quarter * 3, 1)) end
                                                                          as quarter_end_date
from typed
