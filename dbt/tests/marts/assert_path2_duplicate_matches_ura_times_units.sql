-- The duplicate amount on Path 2 is URA x claim units. A row where the engine's amount differs from URA x units
-- by more than a penny means one of the three values was read or computed wrong.
{{ config(severity = 'warn') }}
select dispensing_claim_id, ura, claim_units, duplicate_amount,
       round(ura * claim_units, 2) as expected_amount
from {{ ref('fct_path2_medicaid_340b') }}
where finding_status = 'duplicate_evidenced'
  and abs(duplicate_amount - round(ura * claim_units, 2)) > 0.01
