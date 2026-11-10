-- Each pair appears twice in the mart (once per submission). If submission A lists B as its pair, then B must list A.
-- A row below means the unpivot lost one side of a pair.
{{ config(severity = 'warn') }}
select a.pilot_submission_id, a.paired_pilot_submission_id
from {{ ref('fct_path3_same_fill_diversion') }} a
left join {{ ref('fct_path3_same_fill_diversion') }} b
    on b.pilot_submission_id = a.paired_pilot_submission_id
   and b.paired_pilot_submission_id = a.pilot_submission_id
where b.pilot_submission_id is null
