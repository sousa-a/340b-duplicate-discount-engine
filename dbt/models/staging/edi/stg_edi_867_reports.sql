-- stg_edi_867_reports
-- One row per EDI 867 transaction set (one wholesaler, manufacturer and reporting week), with the control totals
-- as sent: CTT and AMT*TT (sum of the extended amounts). Tests compare them with stg_edi_867_sales_lines.
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with segments as (

    select * from {{ source('raw', 'edi_867_segments') }}
    where st_control_number is not null

),

envelope as (

    select
        _source_file,
        gs_control_number,
        {{ x12_el(2) }}                                                                     as wholesaler_id,
        {{ x12_el(3) }}                                                                     as manufacturer_code
    from {{ source('raw', 'edi_867_segments') }}
    where segment_id = 'GS'

),

reports as (

    select
        _source_file,
        gs_control_number,
        st_control_number,
        max(case when segment_id = 'BPT' then {{ x12_el(2) }} end)                          as report_reference,
        max(case when segment_id = 'BPT' then {{ x12_date(3) }} end)                        as report_date,
        max(case when segment_id = 'DTM' and {{ x12_el(1) }} = '090' then {{ x12_date(2) }} end) as period_start_date,
        max(case when segment_id = 'DTM' and {{ x12_el(1) }} = '091' then {{ x12_date(2) }} end) as period_end_date,
        sum(case when segment_id = 'PTD' then 1 else 0 end)                                 as ship_to_groups,
        sum(case when segment_id = 'SII' then 1 else 0 end)                                 as lines_found,
        max(case when segment_id = 'AMT' and {{ x12_el(1) }} = 'TT'
                 then try_cast({{ x12_el(2) }} as decimal(18, 2)) end)                      as total_amount_declared
    from segments
    group by _source_file, gs_control_number, st_control_number

)

select
    r._source_file,
    r.st_control_number,
    e.wholesaler_id,
    e.manufacturer_code,
    r.report_reference,
    r.report_date,
    r.period_start_date,
    r.period_end_date,
    r.ship_to_groups,
    r.lines_found,
    r.total_amount_declared
from reports r
join envelope e
    on e._source_file = r._source_file and e.gs_control_number = r.gs_control_number
