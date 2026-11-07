-- Primary key of int_340b_pathways: pharmacy_npi, ce_340b_id, pathway_type, medicaid_state_code, valid_from. Error severity.
select pharmacy_npi, ce_340b_id, pathway_type, medicaid_state_code, valid_from, count(*) as rows_for_key
from {{ ref('int_340b_pathways') }}
group by pharmacy_npi, ce_340b_id, pathway_type, medicaid_state_code, valid_from
having count(*) > 1
