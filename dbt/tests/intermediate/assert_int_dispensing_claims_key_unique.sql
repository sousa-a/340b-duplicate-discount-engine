-- Primary key of int_dispensing_claims: source, source_record_id. Error severity.
select source, source_record_id, count(*) as rows_for_key
from {{ ref('int_dispensing_claims') }}
group by source, source_record_id
having count(*) > 1
