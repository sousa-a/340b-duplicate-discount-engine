-- Every same-fill pair must involve two different covered entities. A row where ce_340b_id equals paired_ce_340b_id
-- means int_claim_matches produced a self-pair that should have been filtered out.
{{ config(severity = 'error') }}
select pilot_submission_id, ce_340b_id, paired_ce_340b_id
from {{ ref('fct_path3_same_fill_diversion') }}
where ce_340b_id = paired_ce_340b_id
