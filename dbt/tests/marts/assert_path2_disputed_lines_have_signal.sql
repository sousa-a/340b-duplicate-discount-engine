-- Every row in the Path 2 mart must come from a disputed invoice line, which means the 340B signal that triggered the
-- dispute must be positive. A row with zero signal submissions should never reach the mart.
{{ config(severity = 'warn') }}
select invoice_file, line_number, ndc11, state_code, signal_submissions
from {{ ref('fct_path2_medicaid_340b') }}
where signal_submissions <= 0
