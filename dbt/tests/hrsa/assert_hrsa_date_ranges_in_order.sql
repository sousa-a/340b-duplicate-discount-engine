-- Every date range in the HRSA files must end on or after it starts. Returns the rows that do not.
{{ config(severity = 'warn') }}
select 'covered entity' as file, ce_340b_id, participation_start_date as range_start, termination_date as range_end
from {{ ref('stg_hrsa_covered_entities') }}
where termination_date < participation_start_date
union all
select 'contract pharmacy', ce_340b_id, contract_start_date, contract_end_date
from {{ ref('stg_hrsa_contract_pharmacies') }}
where contract_end_date < contract_start_date
union all
select 'medicaid exclusion file', ce_340b_id, effective_from, effective_to
from {{ ref('stg_hrsa_medicaid_exclusion_file') }}
where effective_to < effective_from
