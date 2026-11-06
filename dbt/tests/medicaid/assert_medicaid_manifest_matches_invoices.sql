-- The manifest and the invoice files must agree: every file listed was received, every file received is listed,
-- and the number of lines matches. Returns the files that disagree.
{{ config(severity = 'warn') }}
with lines as (
    select _source_file as invoice_file, count(*) as lines_found
    from {{ ref('stg_medicaid_invoice_lines') }}
    group by _source_file
)
select coalesce(m.invoice_file, l.invoice_file) as invoice_file, m.lines_declared, l.lines_found
from {{ ref('stg_medicaid_invoice_manifest') }} m
full outer join lines l on l.invoice_file = m.invoice_file
where m.lines_declared is distinct from l.lines_found
