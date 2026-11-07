-- Primary key of int_claim_340b_evidence: source, source_record_id. Error severity.
select source, source_record_id, count(*) as rows_for_key
from {{ ref('int_claim_340b_evidence') }}
group by source, source_record_id
having count(*) > 1
