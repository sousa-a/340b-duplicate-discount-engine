-- No match may be further apart than the configured tolerance (guards the join condition against edits).
select left_source, left_record_id, right_source, right_record_id, date_difference_days
from {{ ref('int_claim_matches') }}
where date_difference_days > {{ var('date_match_tolerance_days') }}
