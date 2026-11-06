-- stg_hrsa_covered_entities
-- Covered entities as HRSA publishes them in OPAIS (Office of Pharmacy Affairs Information System), one row per
-- 340B ID. An entity is active from participation_start_date until termination_date (open when empty).
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

select
    ce_340b_id,
    ce_name,
    opais_entity_type,
    state_code,
    try_cast(participation_start_date as date)                       as participation_start_date,
    try_cast(termination_date as date)                               as termination_date,
    termination_date is null                                         as has_no_termination_date,
    _source_file,
    _ingested_at
from {{ source('raw', 'hrsa_opais_covered_entities') }}
