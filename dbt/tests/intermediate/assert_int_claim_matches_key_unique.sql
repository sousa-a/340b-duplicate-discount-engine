-- Primary key of int_claim_matches: left_source, left_record_id, right_source, right_record_id. Error severity.
select left_source, left_record_id, right_source, right_record_id, count(*) as rows_for_key
from {{ ref('int_claim_matches') }}
group by left_source, left_record_id, right_source, right_record_id
having count(*) > 1
