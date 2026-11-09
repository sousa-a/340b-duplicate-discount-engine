-- Every Path 2 row with finding_status duplicate_evidenced must carry a positive duplicate amount. A row without one
-- means the URA or claim units were null or zero, which should not happen on a valid invoice line with claim detail.
{{ config(severity = 'warn') }}
select dispensing_claim_id, ndc11, date_of_service, evidence_basis, ura, claim_units, duplicate_amount
from {{ ref('fct_path2_medicaid_340b') }}
where finding_status = 'duplicate_evidenced'
  and (duplicate_amount is null or duplicate_amount <= 0)
