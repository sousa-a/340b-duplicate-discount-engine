-- 340B purchases whose ship-to pharmacy could not be linked to an NPI, one row per pharmacy with its line count.
-- These purchases cannot support any claim. A warning, because the gap is a property of the data a manufacturer
-- receives (the 844 names pharmacies by name and DEA number; only contract pharmacies have a public name-to-NPI link),
-- and the size of the gap is what this test reports.
{{ config(severity = 'warn') }}
select ship_to_name, ship_to_dea, count(*) as purchase_lines, sum(chargeback_amount) as chargeback_amount
from {{ ref('int_340b_purchases') }}
where pharmacy_link_method = 'unlinked'
group by ship_to_name, ship_to_dea
