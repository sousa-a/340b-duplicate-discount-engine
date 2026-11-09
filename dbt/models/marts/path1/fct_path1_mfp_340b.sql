-- fct_path1_mfp_340b
-- Path 1, MFP and 340B duplicate discounts on Medicare Part D. One row per MTF claim that was not reversed and has a
-- refund decision from the manufacturer. Each row says what the manufacturer's data shows: whether the full MFP
-- refund was paid, whether there is evidence the same fill also got the 340B price, and if both, the duplicate amount.
--
-- The rule (Inflation Reduction Act, Social Security Act section 1193(d)): a manufacturer does not owe the MFP refund
-- on a unit that got the 340B price where the 340B ceiling price is below the MFP (d)(1); where the MFP is below the
-- ceiling it owes only the difference, ceiling minus MFP (d)(2). So when both concessions were given in full, the
-- duplicate is the smaller one:
--     duplicate = quantity x (WAC - the higher of MFP and ceiling price)
-- which is the full 340B discount when the MFP is lower and the full MFP refund when the ceiling is lower. IQVIA's
-- 2026 study counts duplicates the same way (Sun et al. 2026).
--
-- finding_status:
--   duplicate_evidenced        full MFP refund paid (code 1) and evidence the fill got the 340B price:
--                              a Pilot rebate paid for the same fill, the pharmacy's 340B flag, or a 340B purchase
--                              for that pharmacy and NDC after the fill on a registered or observed route
--   nonduplication_applied     the manufacturer already paid code 4 or 8 on this claim
--   pilot_rebate_not_paid      the fill went to the Pilot, but no rebate was paid (denied or rejected), so the 340B
--                              price was not given and the MFP refund stands
--   evidence_insufficient      refund paid, the pharmacy is a 340B route, but nothing ties this fill to 340B stock
--   no_340b_evidence           refund paid and nothing in the data points to 340B
--
-- The finding is evidence for an MTF refund adjustment or, for Pilot drugs where the MFP is the lower price, the
-- Pilot's MFP nonduplication ground. The engine does not recommend an outcome.
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with claims as (

    select
        d.source_record_id                                                as mtf_icn,
        d.manufacturer_code,
        d.pharmacy_npi,
        d.rx_number_normalized,
        d.fill_number,
        d.ndc11,
        d.date_of_service,
        d.quantity,
        c.wac_per_unit,
        c.mfp_per_unit,
        c.sdra,
        c._source_file
    from {{ ref('int_dispensing_claims') }} d
    join {{ ref('stg_mtf_claims') }} c
        on c.mtf_icn = d.source_record_id
    where d.source = 'mtf'

),

payments as (

    select mtf_icn, refund_method_code, refund_amount, remark_code, payment_date
    from {{ ref('stg_mtf_payments') }}
    where not is_reversal

),

pilot_paid as (

    -- Pilot submissions matched to the MTF claim whose rebate was paid; the unit 340B price is the ceiling the
    -- manufacturer itself used for that fill
    select
        case when m.left_source = 'mtf' then m.left_record_id else m.right_record_id end   as mtf_icn,
        count(*)                                                          as paid_submissions,
        max(r.unit_340b_price)                                            as unit_340b_price,
        sum(r.rebate_amount)                                              as pilot_rebate_paid
    from {{ ref('int_claim_matches') }} m
    join {{ ref('stg_pilot_rebate_status') }} r
        on r.submission_id = case when m.left_source = 'pilot' then m.left_record_id else m.right_record_id end
    where ((m.left_source = 'mtf' and m.right_source = 'pilot') or (m.left_source = 'pilot' and m.right_source = 'mtf'))
      and r.is_paid
    group by 1

),

ceiling_ratio_pilot as (

    select manufacturer_code, ndc11, quarter_start_date, quarter_end_date,
           ceiling_price_per_package / wac_per_package                    as ceiling_to_wac
    from {{ ref('stg_pilot_ceiling_prices') }}
    where wac_per_package > 0

),

ceiling_ratio_844 as (

    select
        ndc11,
        date_trunc('quarter', invoice_date)                               as quarter_start_date,
        avg(contract_price_per_package / wac_per_package)                 as ceiling_to_wac
    from {{ ref('stg_edi_844_chargeback_lines') }}
    where wac_per_package > 0
    group by 1, 2

),

priced as (

    select
        c.*,
        p.refund_method_code,
        p.refund_amount,
        p.remark_code,
        p.payment_date,
        pp.paid_submissions,
        pp.pilot_rebate_paid,
        case
            when pp.unit_340b_price is not null then pp.unit_340b_price
            when rp.ceiling_to_wac is not null then c.wac_per_unit * rp.ceiling_to_wac
            when r8.ceiling_to_wac is not null then c.wac_per_unit * r8.ceiling_to_wac
        end                                                               as ceiling_per_unit,
        case
            when pp.unit_340b_price is not null then 'pilot_rebate_unit_price'
            when rp.ceiling_to_wac is not null then 'pilot_ceiling_file_ratio'
            when r8.ceiling_to_wac is not null then 'chargeback_contract_price_ratio'
        end                                                               as ceiling_source
    from claims c
    join payments p
        on p.mtf_icn = c.mtf_icn
    left join pilot_paid pp
        on pp.mtf_icn = c.mtf_icn
    left join ceiling_ratio_pilot rp
        on rp.manufacturer_code = c.manufacturer_code and rp.ndc11 = c.ndc11
       and c.date_of_service between rp.quarter_start_date and rp.quarter_end_date
    left join ceiling_ratio_844 r8
        on r8.ndc11 = c.ndc11 and r8.quarter_start_date = date_trunc('quarter', c.date_of_service)

),

assessed as (

    select
        p.*,
        e.evidence_level,
        e.is_flagged_340b,
        e.pilot_submissions,
        e.pilot_statuses,
        e.pilot_ce_340b_ids,
        e.purchase_lines,
        e.purchase_ce_340b_ids,
        e.pathway_ce_340b_ids,
        e.observed_route_ce_340b_ids,
        p.refund_method_code = '1' and p.refund_amount > 0                as full_mfp_refund_paid,
        coalesce(p.paid_submissions, 0) > 0
            or e.is_flagged_340b
            or e.evidence_level in ('pathway_and_purchase', 'observed_route_and_purchase')
                                                                          as has_340b_given_evidence,
        case
            when coalesce(p.paid_submissions, 0) > 0 then 'pilot_rebate_paid'
            when e.is_flagged_340b then 'pharmacy_340b_flag'
            when e.evidence_level = 'pathway_and_purchase' then 'registered_route_and_340b_purchase'
            when e.evidence_level = 'observed_route_and_purchase' then 'observed_route_and_340b_purchase'
        end                                                               as evidence_basis
    from priced p
    join {{ ref('int_claim_340b_evidence') }} e
        on e.source = 'mtf' and e.source_record_id = p.mtf_icn

)

select
    -- the claim
    cast(mtf_icn as string)                                               as mtf_icn,
    cast(manufacturer_code as string)                                     as manufacturer_code,
    cast(pharmacy_npi as string)                                          as pharmacy_npi,
    cast(rx_number_normalized as string)                                  as rx_number_normalized,
    cast(fill_number as int)                                              as fill_number,
    cast(ndc11 as string)                                                 as ndc11,
    cast(date_of_service as date)                                         as date_of_service,
    cast(year(date_of_service) as int)                                    as service_year,
    cast(quantity as decimal(14, 3))                                      as quantity,

    -- the MFP refund
    cast(refund_method_code as string)                                    as refund_method_code,
    cast(refund_amount as decimal(18, 2))                                 as refund_amount,
    cast(full_mfp_refund_paid as boolean)                                 as full_mfp_refund_paid,

    -- prices per unit
    cast(wac_per_unit as decimal(18, 6))                                  as wac_per_unit,
    cast(mfp_per_unit as decimal(18, 6))                                  as mfp_per_unit,
    cast(ceiling_per_unit as decimal(18, 6))                              as ceiling_per_unit,
    cast(ceiling_source as string)                                        as ceiling_source,
    cast(case when ceiling_per_unit is null then null
              when ceiling_per_unit < mfp_per_unit then 'd1_ceiling_below_mfp'
              else 'd2_mfp_below_ceiling' end as string)                  as nonduplication_case,

    -- the 340B evidence
    cast(evidence_level as string)                                        as evidence_level,
    cast(evidence_basis as string)                                        as evidence_basis,
    cast(coalesce(paid_submissions, 0) as bigint)                         as pilot_paid_submissions,
    cast(pilot_rebate_paid as decimal(18, 2))                             as pilot_rebate_paid,
    pilot_statuses,
    pilot_ce_340b_ids,
    purchase_ce_340b_ids,
    pathway_ce_340b_ids,
    observed_route_ce_340b_ids,

    -- the finding
    cast(case
        when refund_method_code in ('4', '8') then 'nonduplication_applied'
        when not full_mfp_refund_paid then 'no_refund_paid'
        when has_340b_given_evidence then 'duplicate_evidenced'
        when coalesce(pilot_submissions, 0) > 0 then 'pilot_rebate_not_paid'
        when evidence_level in ('pathway_only', 'observed_route_only') then 'evidence_insufficient'
        else 'no_340b_evidence'
    end as string)                                                        as finding_status,
    cast(case
        when full_mfp_refund_paid and has_340b_given_evidence and ceiling_per_unit is not null
            then round(quantity * (wac_per_unit - greatest(mfp_per_unit, ceiling_per_unit)), 2)
    end as decimal(18, 2))                                                as duplicate_amount,
    cast(case
        when not (full_mfp_refund_paid and has_340b_given_evidence) then null
        when coalesce(paid_submissions, 0) > 0 and ceiling_per_unit >= mfp_per_unit
            then 'pilot_mfp_nonduplication_ground'
        else 'mtf_refund_adjustment'
    end as string)                                                        as rules_channel,

    -- which datasets the finding rests on (the Pilot Notice limits the use of Pilot data to named purposes)
    filter(array(
        'mtf_claims', 'mtf_payments',
        case when coalesce(pilot_submissions, 0) > 0 then 'pilot_submissions' end,
        case when coalesce(paid_submissions, 0) > 0 then 'pilot_rebate_status' end,
        case when coalesce(purchase_lines, 0) > 0 then 'edi_844_chargebacks' end,
        case when coalesce(purchase_lines, 0) > 0 then 'pharmacy_directory' end,
        case when pathway_ce_340b_ids is not null and size(pathway_ce_340b_ids) > 0 then 'hrsa_opais_or_mef' end,
        case when ceiling_source = 'pilot_ceiling_file_ratio' then 'pilot_ceiling_prices' end
    ), x -> x is not null)                                                as datasets_used,

    cast(_source_file as string)                                          as _source_file
from assessed
