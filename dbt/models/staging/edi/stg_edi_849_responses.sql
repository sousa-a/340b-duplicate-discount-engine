-- stg_edi_849_responses
-- One row per EDI 849 transaction set: the manufacturer's answer to one debit memo (Cencora I849 V4010 guide).
--     BRC      response date and credit memo number
--     REF*AM   the debit memo being answered
--     REF*ZZ   number of lines the wholesaler submitted
--     CTT      number of lines in error (disputed)
--     AMT*S    amount submitted, AMT*NA net adjustment (amount disputed), AMT*A amount accepted
-- The 849 is the manufacturer's own outgoing file; it sits in the inbox because it is part of the record the engine
-- reconciles. Sender is the manufacturer (GS02), receiver the wholesaler (GS03).
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with segments as (

    select * from {{ source('raw', 'edi_849_segments') }}
    where st_control_number is not null

),

envelope as (

    select
        _source_file,
        gs_control_number,
        {{ x12_el(2) }}                                                                     as manufacturer_code,
        {{ x12_el(3) }}                                                                     as wholesaler_id
    from {{ source('raw', 'edi_849_segments') }}
    where segment_id = 'GS'

),

responses as (

    select
        _source_file,
        gs_control_number,
        st_control_number,
        max(case when segment_id = 'BRC' then {{ x12_date(2) }} end)                        as response_date,
        max(case when segment_id = 'BRC' then {{ x12_el(4) }} end)                          as credit_memo_number,
        max(case when segment_id = 'REF' and {{ x12_el(1) }} = 'AM' then {{ x12_el(2) }} end) as debit_memo_number,
        max(case when segment_id = 'REF' and {{ x12_el(1) }} = 'ZZ'
                 then try_cast({{ x12_el(2) }} as int) end)                                 as lines_submitted,
        max(case when segment_id = 'CTT' then try_cast({{ x12_el(1) }} as int) end)         as lines_in_error,
        max(case when segment_id = 'AMT' and {{ x12_el(1) }} = 'S'
                 then try_cast({{ x12_el(2) }} as decimal(18, 2)) end)                      as submitted_amount,
        max(case when segment_id = 'AMT' and {{ x12_el(1) }} = 'NA'
                 then try_cast({{ x12_el(2) }} as decimal(18, 2)) end)                      as net_adjustment_amount,
        max(case when segment_id = 'AMT' and {{ x12_el(1) }} = 'A'
                 then try_cast({{ x12_el(2) }} as decimal(18, 2)) end)                      as accepted_amount
    from segments
    group by _source_file, gs_control_number, st_control_number

)

select
    r.debit_memo_number,
    r.credit_memo_number,
    r.response_date,
    e.manufacturer_code,
    e.wholesaler_id,
    r.lines_submitted,
    r.lines_in_error,
    r.submitted_amount,
    r.net_adjustment_amount,
    r.accepted_amount,
    r._source_file,
    r.st_control_number
from responses r
join envelope e
    on e._source_file = r._source_file and e.gs_control_number = r.gs_control_number
