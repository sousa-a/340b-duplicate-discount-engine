-- fct_path2_medicaid_340b
-- Path 2, Medicaid and 340B duplicate discounts. One row per claim on a disputed CMS-R-144 invoice line where the
-- manufacturer has claim-level evidence that the fill was 340B-effectuated.
--
-- Detection (two stages):
--   Stage 1  The manufacturer aggregates 340B rebate submissions (Pilot) that carry a Medicaid BIN/PCN to
--            state x NDC x quarter. When those units overlap with a CMS-R-144 invoice line, the line is disputed
--            and the manufacturer requests claim-level detail from the state (int_medicaid_340b_signal,
--            int_medicaid_invoice_disputes).
--   Stage 2  For each claim behind a disputed line, the shared eligibility layer (int_claim_340b_evidence) says
--            whether the manufacturer's data shows that the fill was 340B-effectuated. Claims with claim-level or
--            pathway-and-purchase evidence are flagged. The duplicate is the rebate the state claimed on those units:
--            URA x claim units.
--
-- finding_status:
--   duplicate_evidenced        the claim is on a disputed invoice line and 340B evidence ties it to a covered entity
--   evidence_insufficient      the pharmacy is a 340B route, but nothing ties this fill to 340B stock
--   no_340b_evidence           nothing in the manufacturer's data points to 340B on this claim
--
-- The finding is evidence for a Medicaid rebate dispute. The engine does not recommend an outcome.
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with disputes as (

    select * from {{ ref('int_medicaid_invoice_disputes') }}

),

assessed as (

    select
        d.*,

        -- has evidence strong enough to flag?
        coalesce(d.claim_pilot_submissions, 0) > 0
            or d.evidence_level in ('claim_level', 'pathway_and_purchase', 'observed_route_and_purchase')
                                                                              as has_340b_given_evidence,

        case
            when coalesce(d.claim_pilot_submissions, 0) > 0 then 'pilot_submission_matched'
            when d.evidence_level = 'claim_level' then 'pharmacy_340b_flag'
            when d.evidence_level = 'pathway_and_purchase' then 'registered_route_and_340b_purchase'
            when d.evidence_level = 'observed_route_and_purchase' then 'observed_route_and_340b_purchase'
        end                                                                   as evidence_basis

    from disputes d

)

select
    -- invoice line
    cast(invoice_file as string)                                              as invoice_file,
    cast(line_number as int)                                                  as line_number,
    cast(manufacturer_code as string)                                         as manufacturer_code,
    cast(state_code as string)                                                as state_code,
    cast(ndc11 as string)                                                     as ndc11,
    cast(utilization_type_code as string)                                     as utilization_type_code,
    cast(utilization_type as string)                                          as utilization_type,
    cast(period_covered as string)                                            as period_covered,
    cast(quarter_start_date as date)                                          as quarter_start_date,
    cast(quarter_end_date as date)                                            as quarter_end_date,

    -- invoice line amounts
    cast(ura as decimal(15, 6))                                               as ura,
    cast(units_reimbursed as decimal(16, 3))                                  as units_reimbursed,
    cast(rebate_amount_claimed as decimal(16, 2))                             as rebate_amount_claimed,

    -- the 340B signal that triggered the dispute
    cast(signal_submissions as bigint)                                        as signal_submissions,
    cast(signal_units as decimal(16, 3))                                      as signal_units,

    -- the claim behind the invoice line
    cast(dispensing_claim_id as string)                                        as dispensing_claim_id,
    cast(pharmacy_npi as string)                                              as pharmacy_npi,
    cast(rx_number_normalized as string)                                      as rx_number_normalized,
    cast(fill_number as int)                                                  as fill_number,
    cast(date_of_service as date)                                             as date_of_service,
    cast(claim_units as decimal(14, 3))                                       as claim_units,
    cast(claim_medicaid_amount as decimal(16, 2))                             as claim_medicaid_amount,

    -- 340B evidence on the claim
    cast(evidence_level as string)                                            as evidence_level,
    cast(evidence_basis as string)                                            as evidence_basis,
    cast(coalesce(claim_pilot_submissions, 0) as bigint)                      as pilot_submissions,
    claim_pilot_ce_340b_ids                                                   as pilot_ce_340b_ids,
    claim_pilot_statuses                                                      as pilot_statuses,
    claim_purchase_ce_340b_ids                                                as purchase_ce_340b_ids,
    claim_pathway_ce_340b_ids                                                 as pathway_ce_340b_ids,
    claim_observed_route_ce_340b_ids                                          as observed_route_ce_340b_ids,

    -- the finding
    cast(case
        when has_340b_given_evidence then 'duplicate_evidenced'
        when evidence_level in ('pathway_only', 'observed_route_only') then 'evidence_insufficient'
        else 'no_340b_evidence'
    end as string)                                                            as finding_status,

    -- duplicate amount: URA x claim units (Medicaid exposure = rebate paid on 340B units)
    cast(case
        when has_340b_given_evidence
            then round(ura * claim_units, 2)
    end as decimal(18, 2))                                                    as duplicate_amount,

    -- which datasets the finding rests on
    filter(array(
        'cms_r144_invoices',
        'state_claim_level_detail',
        case when coalesce(claim_pilot_submissions, 0) > 0 then 'pilot_submissions' end,
        case when coalesce(claim_purchase_lines, 0) > 0 then 'edi_844_chargebacks' end,
        case when claim_pathway_ce_340b_ids is not null and size(claim_pathway_ce_340b_ids) > 0
             then 'hrsa_opais_or_mef' end
    ), x -> x is not null)                                                    as datasets_used,

    cast(detail_source_file as string)                                        as _source_file

from assessed
