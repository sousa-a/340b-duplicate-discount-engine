-- Primary key of stg_medicaid_invoice_lines: file and line number. Error severity.
select _source_file, line_number, count(*) as rows_for_key
from {{ ref('stg_medicaid_invoice_lines') }}
group by _source_file, line_number
having count(*) > 1
