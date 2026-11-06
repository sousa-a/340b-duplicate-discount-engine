-- stg_hrsa_medicaid_exclusion_file
-- Medicaid Exclusion File (MEF): billing NPIs through which a covered entity bills Medicaid fee for service with
-- 340B drugs ("carve in"), so a state must leave those claims out of its rebate invoices. One row per entity, state,
-- billing NPI and start date; in force from effective_from until effective_to (open when empty).
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

select
    ce_340b_id,
    state_code,
    billing_npi,
    try_cast(effective_from as date)                                 as effective_from,
    try_cast(effective_to as date)                                   as effective_to,
    _source_file,
    _ingested_at
from {{ source('raw', 'hrsa_medicaid_exclusion_file') }}
