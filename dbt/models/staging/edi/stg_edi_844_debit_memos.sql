-- stg_edi_844_debit_memos
-- One row per EDI 844 transaction set, which is one debit memo: the header (BAA, N1*DB, N1*SU) and the control
-- totals at the end (CTT, number of lines; AMT*CC, total chargeback amount). The totals are kept as sent so tests
-- can compare them with the lines in stg_edi_844_chargeback_lines.
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with segments as (

    select * from {{ source('raw', 'edi_844_segments') }}
    where st_control_number is not null

),

envelope as (

    select
        _source_file,
        gs_control_number,
        {{ x12_el(2) }}                                                                     as wholesaler_id,
        {{ x12_el(3) }}                                                                     as manufacturer_code
    from {{ source('raw', 'edi_844_segments') }}
    where segment_id = 'GS'

),

memos as (

    select
        _source_file,
        gs_control_number,
        st_control_number,
        max(case when segment_id = 'BAA' then {{ x12_el(1) }} end)                          as purpose_code,
        max(case when segment_id = 'BAA' then {{ x12_el(5) }} end)                          as debit_memo_number,
        max(case when segment_id = 'BAA' then {{ x12_date(3) }} end)                        as debit_memo_date,
        max(case when segment_id = 'N1' and {{ x12_el(1) }} = 'DB' then {{ x12_el(4) }} end) as wholesaler_branch_dea,
        max(case when segment_id = 'N1' and {{ x12_el(1) }} = 'SU' then {{ x12_el(4) }} end) as supplier_dea,
        sum(case when segment_id = 'CON' then 1 else 0 end)                                 as lines_found,
        max(case when segment_id = 'CTT' then try_cast({{ x12_el(1) }} as int) end)         as lines_declared,
        max(case when segment_id = 'AMT' and {{ x12_el(1) }} = 'CC'
                 then try_cast({{ x12_el(2) }} as decimal(18, 2)) end)                      as total_amount_declared
    from segments
    group by _source_file, gs_control_number, st_control_number

)

select
    m.debit_memo_number,
    m.debit_memo_date,
    m.purpose_code,
    e.wholesaler_id,
    e.manufacturer_code,
    m.wholesaler_branch_dea,
    m.supplier_dea,
    m.lines_found,
    m.lines_declared,
    m.total_amount_declared,
    m._source_file,
    m.st_control_number
from memos m
join envelope e
    on e._source_file = m._source_file and e.gs_control_number = m.gs_control_number
