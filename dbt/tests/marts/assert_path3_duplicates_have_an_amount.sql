-- Every Path 3 row with finding_status duplicate_evidenced must carry a positive duplicate amount. A row without one
-- means the rebate amount was null or zero on a PAID submission, which should not happen.
{{ config(severity = 'warn') }}
select pilot_submission_id, ndc11, date_of_service, rebate_status, rebate_amount, duplicate_amount
from {{ ref('fct_path3_same_fill_diversion') }}
where finding_status = 'duplicate_evidenced'
  and (duplicate_amount is null or duplicate_amount <= 0)
