-- Every Path 1 row with finding_status duplicate_evidenced must carry a positive duplicate amount. A row without one
-- means no ceiling price was found for the fill (no paid Pilot rebate, no ceiling file, no chargeback in that quarter).
{{ config(severity = 'warn') }}
select mtf_icn, ndc11, date_of_service, evidence_basis, ceiling_source, duplicate_amount
from {{ ref('fct_path1_mfp_340b') }}
where finding_status = 'duplicate_evidenced'
  and (duplicate_amount is null or duplicate_amount <= 0)
