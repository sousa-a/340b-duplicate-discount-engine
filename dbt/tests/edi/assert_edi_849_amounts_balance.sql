-- Each 849 response must balance: submitted = accepted + disputed (AMT*S = AMT*A + AMT*NA), and the amount
-- submitted must be the total of the debit memo it answers. Returns the responses that do not.
{{ config(severity = 'warn') }}
select r.debit_memo_number, r.submitted_amount, r.accepted_amount, r.net_adjustment_amount,
       m.total_amount_declared as debit_memo_total
from {{ ref('stg_edi_849_responses') }} r
left join {{ ref('stg_edi_844_debit_memos') }} m on m.debit_memo_number = r.debit_memo_number
where r.submitted_amount is distinct from r.accepted_amount + r.net_adjustment_amount
   or r.submitted_amount is distinct from m.total_amount_declared
