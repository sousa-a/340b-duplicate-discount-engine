-- Primary key of stg_hrsa_contract_pharmacies: entity, pharmacy and start date. Error severity.
select ce_340b_id, pharmacy_npi, contract_start_date, count(*) as rows_for_key
from {{ ref('stg_hrsa_contract_pharmacies') }}
group by ce_340b_id, pharmacy_npi, contract_start_date
having count(*) > 1
