-- stg_edi_844_chargeback_lines
-- One row per chargeback line of the EDI 844 files: a wholesaler asking the manufacturer to pay back the difference
-- between WAC and the 340B contract price for a sale to a covered entity's account.
--
-- The raw table has one row per X12 segment. This model rebuilds the lines from the loop structure of the 844
-- (Cencora O844 V4010 guide): after the header (BAA, N1*DB, N1*SU) every line is the group
--     CON*VC   contract the sale was made under
--     N1*ST    ship-to pharmacy (name, DEA)
--     REF*2U   340B ID of the covered entity whose account bought the drug
--     SII*ND   NDC, quantity in packages, WAC and contract price per package, chargeback amount
--     N9*DI    wholesaler invoice number and date; element 07 holds the sale line ID as the composite L1>id
-- Every line starts with CON, so the running count of CON segments numbers the lines (macro x12_loop_number);
-- grouping by that number puts the five segments of a line on one row.
--
-- Sender and receiver come from the GS segment of the same group (GS02 wholesaler, GS03 manufacturer).
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with segments as (

    select
        *,
        {{ x12_loop_number('CON') }} as line_number
    from {{ source('raw', 'edi_844_segments') }}
    where st_control_number is not null

),

memo_header as (

    select
        _source_file,
        st_control_number,
        max(case when segment_id = 'BAA' then {{ x12_el(5) }} end)                          as debit_memo_number,
        max(case when segment_id = 'BAA' then {{ x12_date(3) }} end)                        as debit_memo_date
    from segments
    where line_number = 0
    group by _source_file, st_control_number

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

lines as (

    select
        _source_file,
        gs_control_number,
        st_control_number,
        line_number,
        min(segment_position)                                                               as first_segment_position,
        max(case when segment_id = 'CON' then {{ x12_el(2) }} end)                          as contract_number,
        max(case when segment_id = 'N1' and {{ x12_el(1) }} = 'ST' then {{ x12_el(2) }} end) as ship_to_name,
        max(case when segment_id = 'N1' and {{ x12_el(1) }} = 'ST' then {{ x12_el(4) }} end) as ship_to_dea,
        -- REF*2U is counted apart from its value: a line can carry the segment with a blank ID
        sum(case when segment_id = 'REF' and {{ x12_el(1) }} = '2U' then 1 else 0 end)      as ref_2u_segments,
        max(case when segment_id = 'REF' and {{ x12_el(1) }} = '2U' then {{ x12_el(2) }} end) as customer_340b_id,
        max(case when segment_id = 'SII' then {{ x12_el(1) }} end)                          as product_id_qualifier,
        max(case when segment_id = 'SII' then {{ x12_el(2) }} end)                          as ndc11,
        max(case when segment_id = 'SII' then {{ x12_el(3) }} end)                          as quantity_text,
        max(case when segment_id = 'SII' then {{ x12_el(4) }} end)                          as unit_of_measure,
        max(case when segment_id = 'SII' then {{ x12_el(5) }} end)                          as wac_text,
        max(case when segment_id = 'SII' then {{ x12_el(6) }} end)                          as contract_price_text,
        max(case when segment_id = 'SII' then {{ x12_el(7) }} end)                          as amount_text,
        max(case when segment_id = 'N9' then {{ x12_el(2) }} end)                           as invoice_number,
        max(case when segment_id = 'N9' then {{ x12_date(4) }} end)                         as invoice_date,
        max(case when segment_id = 'N9' then {{ x12_el(7) }} end)                           as n9_reference
    from segments
    where line_number > 0
      and segment_id in ('CON', 'N1', 'REF', 'SII', 'N9')
    group by _source_file, gs_control_number, st_control_number, line_number

)

select
    -- line identity
    h.debit_memo_number,
    l.line_number,
    case when l.n9_reference like 'L1>%' then substr(l.n9_reference, 4) end                 as sale_line_id,
    h.debit_memo_date,
    e.wholesaler_id,
    e.manufacturer_code,

    -- the sale
    l.contract_number,
    l.ship_to_name,
    l.ship_to_dea,
    l.customer_340b_id,
    l.ref_2u_segments,
    l.invoice_number,
    l.invoice_date,

    -- the drug and the money
    l.product_id_qualifier,
    l.ndc11,
    l.unit_of_measure,
    try_cast(l.quantity_text as decimal(14, 3))                                             as quantity_packages,
    try_cast(l.wac_text as decimal(18, 2))                                                  as wac_per_package,
    try_cast(l.contract_price_text as decimal(18, 2))                                       as contract_price_per_package,
    try_cast(l.amount_text as decimal(18, 2))                                               as chargeback_amount,

    -- lineage: the file, the transaction set and the position of the line's first segment
    l._source_file,
    l.st_control_number,
    l.first_segment_position

from lines l
join memo_header h
    on h._source_file = l._source_file and h.st_control_number = l.st_control_number
join envelope e
    on e._source_file = l._source_file and e.gs_control_number = l.gs_control_number
