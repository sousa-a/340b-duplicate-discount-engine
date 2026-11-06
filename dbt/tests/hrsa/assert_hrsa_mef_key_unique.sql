-- Primary key of stg_hrsa_medicaid_exclusion_file: entity, state, billing NPI and start date. Error severity.
select ce_340b_id, state_code, billing_npi, effective_from, count(*) as rows_for_key
from {{ ref('stg_hrsa_medicaid_exclusion_file') }}
group by ce_340b_id, state_code, billing_npi, effective_from
having count(*) > 1
