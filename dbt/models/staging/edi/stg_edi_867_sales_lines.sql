-- stg_edi_867_sales_lines
-- One row per product line of the EDI 867 Product Transfer and Resale Report: what a wholesaler sold, to which
-- pharmacy, in one reporting week (Cencora O8674121V2 guide). Loop structure of one transaction set:
--     BPT, DTM*090 (period start), DTM*091 (period end), N1*DB     report header
--     PTD*SS                                                       starts a ship-to group
--         N1*ST     the pharmacy (name, DEA)
--         REF*CT    present only when the sale went to a 340B contract account
--         SII*N4    NDC, quantity in packages, WAC per package, extended amount   } one pair
--         N9*DI     wholesaler invoice number and date                              } per line
-- Two loop numbers rebuild this: the running count of PTD gives the ship-to group, the running count of SII the
-- line (N9 follows its SII, so it gets the same number).
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with segments as (

    select
        *,
        {{ x12_loop_number('PTD') }} as ship_to_group,
        {{ x12_loop_number('SII') }} as line_number
    from {{ source('raw', 'edi_867_segments') }}
    where st_control_number is not null

),

report_header as (

    select
        _source_file,
        st_control_number,
        max(case when segment_id = 'BPT' then {{ x12_el(2) }} end)                          as report_reference,
        max(case when segment_id = 'BPT' then {{ x12_date(3) }} end)                        as report_date,
        max(case when segment_id = 'DTM' and {{ x12_el(1) }} = '090' then {{ x12_date(2) }} end) as period_start_date,
        max(case when segment_id = 'DTM' and {{ x12_el(1) }} = '091' then {{ x12_date(2) }} end) as period_end_date
    from segments
    where ship_to_group = 0
    group by _source_file, st_control_number

),

ship_to as (

    select
        _source_file,
        st_control_number,
        ship_to_group,
        max(case when segment_id = 'N1' and {{ x12_el(1) }} = 'ST' then {{ x12_el(2) }} end) as ship_to_name,
        max(case when segment_id = 'N1' and {{ x12_el(1) }} = 'ST' then {{ x12_el(4) }} end) as ship_to_dea,
        max(case when segment_id = 'REF' and {{ x12_el(1) }} = 'CT' then {{ x12_el(2) }} end) as contract_number
    from segments
    where ship_to_group > 0
    group by _source_file, st_control_number, ship_to_group

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

lines as (

    select
        _source_file,
        gs_control_number,
        st_control_number,
        ship_to_group,
        line_number,
        min(segment_position)                                                               as first_segment_position,
        max(case when segment_id = 'SII' then {{ x12_el(1) }} end)                          as product_id_qualifier,
        max(case when segment_id = 'SII' then {{ x12_el(2) }} end)                          as ndc11,
        max(case when segment_id = 'SII' then {{ x12_el(3) }} end)                          as quantity_text,
        max(case when segment_id = 'SII' then {{ x12_el(4) }} end)                          as unit_of_measure,
        max(case when segment_id = 'SII' then {{ x12_el(6) }} end)                          as wac_text,
        max(case when segment_id = 'SII' then {{ x12_el(7) }} end)                          as amount_text,
        max(case when segment_id = 'N9' then {{ x12_el(2) }} end)                           as invoice_number,
        max(case when segment_id = 'N9' then {{ x12_date(4) }} end)                         as invoice_date
    from segments
    where line_number > 0
      and segment_id in ('SII', 'N9')
    group by _source_file, gs_control_number, st_control_number, ship_to_group, line_number

)

select
    l.invoice_number,
    l.invoice_date,
    e.wholesaler_id,
    e.manufacturer_code,
    h.report_date,
    h.period_start_date,
    h.period_end_date,

    s.ship_to_name,
    s.ship_to_dea,
    s.contract_number,
    s.contract_number is not null                                                           as is_340b_account,

    l.product_id_qualifier,
    l.ndc11,
    l.unit_of_measure,
    try_cast(l.quantity_text as decimal(14, 3))                                             as quantity_packages,
    try_cast(l.wac_text as decimal(18, 2))                                                  as wac_per_package,
    try_cast(l.amount_text as decimal(18, 2))                                               as extended_amount,

    l._source_file,
    l.st_control_number,
    l.ship_to_group,
    l.line_number,
    l.first_segment_position

from lines l
join report_header h
    on h._source_file = l._source_file and h.st_control_number = l.st_control_number
join ship_to s
    on s._source_file = l._source_file and s.st_control_number = l.st_control_number
   and s.ship_to_group = l.ship_to_group
join envelope e
    on e._source_file = l._source_file and e.gs_control_number = l.gs_control_number
