-- Within one invoice file, a state reports each NDC once per utilization type (FFSU, MCOU). A repeated NDC and type
-- would double count units. Returns the repeats.
{{ config(severity = 'warn') }}
select _source_file, ndc11, record_id, count(*) as lines
from {{ ref('stg_medicaid_invoice_lines') }}
group by _source_file, ndc11, record_id
having count(*) > 1
