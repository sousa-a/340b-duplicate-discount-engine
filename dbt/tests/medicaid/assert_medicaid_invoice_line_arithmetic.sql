-- Each invoice line must add up: rebate claimed = URA x units reimbursed (to the cent), and total reimbursed =
-- Medicaid + non-Medicaid amount. Returns the lines that do not.
{{ config(severity = 'warn') }}
select _source_file, line_number, ura, units_reimbursed, rebate_amount_claimed,
       round(ura * units_reimbursed, 2) as recomputed_rebate,
       medicaid_amount_reimbursed, non_medicaid_amount_reimbursed, total_amount_reimbursed
from {{ ref('stg_medicaid_invoice_lines') }}
where abs(rebate_amount_claimed - ura * units_reimbursed) > 0.01
   or total_amount_reimbursed <> medicaid_amount_reimbursed + non_medicaid_amount_reimbursed
