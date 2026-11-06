-- The control totals a wholesaler declares on each 844 debit memo must agree with its lines:
-- CTT01 = number of lines, AMT*CC = sum of the line amounts. Returns the memos that disagree.
{{ config(severity = 'warn') }}
with line_totals as (
    select debit_memo_number, count(*) as lines, sum(chargeback_amount) as amount
    from {{ ref('stg_edi_844_chargeback_lines') }}
    group by debit_memo_number
)
select m.debit_memo_number, m.lines_declared, l.lines, m.total_amount_declared, l.amount
from {{ ref('stg_edi_844_debit_memos') }} m
left join line_totals l on l.debit_memo_number = m.debit_memo_number
where m.lines_declared is distinct from l.lines
   or m.lines_declared is distinct from m.lines_found
   or m.total_amount_declared is distinct from l.amount
