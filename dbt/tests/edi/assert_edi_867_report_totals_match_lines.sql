-- The AMT*TT total of each 867 report must equal the sum of its lines' extended amounts, and each extended amount
-- must be quantity x WAC to the cent. Returns the reports that disagree.
{{ config(severity = 'warn') }}
with line_totals as (
    select _source_file, st_control_number, count(*) as lines, sum(extended_amount) as amount,
           sum(case when abs(extended_amount - quantity_packages * wac_per_package) > 0.005 then 1 else 0 end)
               as lines_with_wrong_arithmetic
    from {{ ref('stg_edi_867_sales_lines') }}
    group by _source_file, st_control_number
)
select r._source_file, r.st_control_number, r.lines_found, l.lines, r.total_amount_declared, l.amount,
       l.lines_with_wrong_arithmetic
from {{ ref('stg_edi_867_reports') }} r
left join line_totals l on l._source_file = r._source_file and l.st_control_number = r.st_control_number
where r.lines_found is distinct from l.lines
   or abs(r.total_amount_declared - l.amount) > 0.005
   or l.lines_with_wrong_arithmetic > 0
