-- stg_mtf_claims
-- One row per MTF claim record, renamed and typed. Nothing is joined or filtered here: a staging model is a clean
-- copy of one source, so every later model starts from the same typed columns.
--
-- try_cast is used instead of cast: a value that does not convert becomes NULL instead of stopping the build,
-- and the castable_to tests on the source report exactly which values failed. The build keeps going and the
-- problem shows up as a data quality finding.
--
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with source as (

    select * from {{ source('raw', 'mtf_claims') }}

),

typed as (

    select
        -- identifiers
        mtf_icn,
        mtf_xref_icn,
        record_id,
        transaction_code,
        transaction_code = 'REVERSAL'                              as is_reversal,
        medicare_source_of_coverage,
        contract_number,

        -- when
        try_cast(date_of_service as date)                          as date_of_service,
        try_cast(process_date as date)                             as process_date,

        -- who dispensed and who prescribed
        service_provider_id_qualifier,
        service_provider_id,
        prescriber_id_qualifier,
        prescriber_id,

        -- what was dispensed
        rx_number,
        try_cast(fill_number as int)                               as fill_number,
        ndc11,
        try_cast(quantity_dispensed as decimal(14, 3))             as quantity_dispensed,
        try_cast(days_supply as int)                               as days_supply,

        -- 340B flag sent by the pharmacy: the raw value, and a boolean where empty means not flagged
        indicator_340b,
        coalesce(indicator_340b = 'Y', false)                      as is_flagged_340b,

        -- prices and the refund the MTF computed
        try_cast(wac_per_unit as decimal(18, 6))                   as wac_per_unit,
        try_cast(mfp_per_unit as decimal(18, 6))                   as mfp_per_unit,
        try_cast(sdra as decimal(18, 2))                           as sdra,

        -- lineage
        _source_file,
        _ingested_at

    from source

)

select * from typed
