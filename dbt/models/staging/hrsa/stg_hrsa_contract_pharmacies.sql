-- stg_hrsa_contract_pharmacies
-- Contract pharmacy arrangements registered in OPAIS, one row per covered entity, pharmacy and start date.
-- An arrangement is in force from contract_start_date until contract_end_date (open when empty).
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

select
    ce_340b_id,
    pharmacy_npi,
    pharmacy_name,
    pharmacy_state,
    try_cast(contract_start_date as date)                            as contract_start_date,
    try_cast(contract_end_date as date)                              as contract_end_date,
    _source_file,
    _ingested_at
from {{ source('raw', 'hrsa_opais_contract_pharmacies') }}
