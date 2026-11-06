-- stg_pilot_submissions
-- One row per claim a covered entity submitted through the 340B rebate Pilot, renamed and typed.
--
-- Two fields are standardized here, because they arrive in more than one written form and every later join needs
-- one form. The value as received is kept next to the standardized one, so nothing is lost:
--   NDC        the file column is called ndc11 but entities also send 10-digit hyphenated label forms;
--              ndc11 below is always the 11-digit form (macro normalize_ndc11), ndc_as_submitted is the original
--   Rx number  some entities pad it with leading zeros; rx_number_normalized drops them
-- Anything that needs judgment (a shifted date of service, a quantity sent in packages instead of units) is
-- not touched here: those are matching questions for the intermediate layer.
--
-- The manufacturer is not a column of the file; it comes from the file name (pilot_submissions_MFR001.csv).
--
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with source as (

    select * from {{ source('raw', 'pilot_submissions') }}

),

typed as (

    select
        -- identifiers
        submission_id,
        regexp_extract(_source_file, 'MFR[0-9]{3}', 0)              as manufacturer_code,
        channel,
        ce_340b_id,

        -- when
        try_cast(submission_date as date)                            as submission_date,
        try_cast(date_of_service as date)                            as date_of_service,
        try_cast(date_prescribed as date)                            as date_prescribed,

        -- the prescription
        rx_number,
        nullif(regexp_replace(rx_number, '^0+', ''), '')             as rx_number_normalized,
        try_cast(fill_number as int)                                 as fill_number,

        -- the drug, as submitted and standardized
        ndc11                                                        as ndc_as_submitted,
        {{ ndc_format('ndc11') }}                                    as ndc_format,
        {{ normalize_ndc11('ndc11') }}                               as ndc11,

        try_cast(quantity as decimal(14, 3))                         as quantity,
        try_cast(days_supply as int)                                 as days_supply,

        -- who
        prescriber_npi,
        service_provider_npi,

        -- payer routing
        rx_bin,
        rx_pcn,

        -- lineage
        _source_file,
        _ingested_at

    from source

)

select * from typed
