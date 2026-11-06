-- Primary key of stg_edi_867_reports: file and transaction set. Error severity.
select _source_file, st_control_number, count(*) as rows_for_key
from {{ ref('stg_edi_867_reports') }}
group by _source_file, st_control_number
having count(*) > 1
