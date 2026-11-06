-- Primary key of stg_edi_844_chargeback_lines: one row per debit memo and line number. Error severity.
select debit_memo_number, line_number, count(*) as rows_for_key
from {{ ref('stg_edi_844_chargeback_lines') }}
group by debit_memo_number, line_number
having count(*) > 1
