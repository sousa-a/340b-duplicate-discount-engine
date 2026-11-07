-- int_340b_pathways
-- Every registered route by which a pharmacy could dispense 340B stock for a covered entity, with the dates it was
-- in force. One row per pharmacy NPI, covered entity, route and start date. Two routes are visible to a manufacturer
-- in public HRSA data:
--   contract_pharmacy     an OPAIS contract pharmacy arrangement, cut to the entity's own participation dates
--                         (an arrangement cannot count while the entity is not participating)
--   medicaid_ffs_carve_in a billing NPI the entity listed on the Medicaid Exclusion File for one state: the entity
--                         bills that state's fee for service Medicaid with 340B drugs through this NPI
-- Entity-owned pharmacies that are not on the Medicaid Exclusion File have no public NPI link, so they have no
-- pathway here (see int_340b_purchases for how many 340B purchases this leaves unlinked).
-- This is condition C2 of Martin and Illich (2022), "filled at an entity-owned pharmacy or one of the entity's
-- contract pharmacies", restricted to what public data shows. Condition C1 (prescription written at the entity)
-- needs medical claims a manufacturer does not receive and is not attempted.
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with entities as (

    select
        ce_340b_id,
        opais_entity_type,
        participation_start_date,
        coalesce(termination_date, date '9999-12-31')                     as participation_end_date
    from {{ ref('stg_hrsa_covered_entities') }}

),

contract_pharmacy as (

    select
        cp.pharmacy_npi,
        cp.ce_340b_id,
        'contract_pharmacy'                                               as pathway_type,
        cast(null as string)                                              as medicaid_state_code,
        greatest(cp.contract_start_date, e.participation_start_date)      as valid_from,
        least(coalesce(cp.contract_end_date, date '9999-12-31'), e.participation_end_date) as valid_to
    from {{ ref('stg_hrsa_contract_pharmacies') }} cp
    join entities e
        on e.ce_340b_id = cp.ce_340b_id

),

medicaid_carve_in as (

    select
        mef.billing_npi                                                   as pharmacy_npi,
        mef.ce_340b_id,
        'medicaid_ffs_carve_in'                                           as pathway_type,
        mef.state_code                                                    as medicaid_state_code,
        greatest(mef.effective_from, e.participation_start_date)          as valid_from,
        least(coalesce(mef.effective_to, date '9999-12-31'), e.participation_end_date) as valid_to
    from {{ ref('stg_hrsa_medicaid_exclusion_file') }} mef
    join entities e
        on e.ce_340b_id = mef.ce_340b_id

),

all_pathways as (

    select * from contract_pharmacy
    union all
    select * from medicaid_carve_in

)

select
    p.*,
    e.opais_entity_type
from all_pathways p
join entities e
    on e.ce_340b_id = p.ce_340b_id
-- a range that ends before it starts never overlapped the entity's participation
where p.valid_from <= p.valid_to
