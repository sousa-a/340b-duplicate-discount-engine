-- Primary key of stg_edi_867_sales_lines: file, transaction set and line number. Error severity.
select _source_file, st_control_number, line_number, count(*) as rows_for_key
from {{ ref('stg_edi_867_sales_lines') }}
group by _source_file, st_control_number, line_number
having count(*) > 1
