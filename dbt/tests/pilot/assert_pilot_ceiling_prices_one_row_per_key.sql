-- Primary key of stg_pilot_ceiling_prices: one row per manufacturer, NDC and quarter. A duplicate would give one
-- claim two ceiling prices. Error severity, like every primary key test.
select manufacturer_code, ndc11, year_quarter, count(*) as rows_for_key
from {{ ref('stg_pilot_ceiling_prices') }}
group by manufacturer_code, ndc11, year_quarter
having count(*) > 1
