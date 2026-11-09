-- int_medicaid_invoice_disputes
-- Stage 1 result: CMS-R-144 invoice lines that the manufacturer would dispute because the 340B signal shows overlap
-- between 340B submissions and Medicaid units for that state, NDC and quarter. For disputed lines the manufacturer
-- requests claim-level detail from the state, which is the input to stage 2 (the mart).
--
-- A line is disputed when has_340b_signal is true, meaning the manufacturer received at least one Pilot submission
-- with a Medicaid BIN/PCN for the same state, NDC and quarter. The manufacturer does not dispute lines where it has
-- no signal, even if 340B units might be on them: absent a submission, it has no evidence.
--
-- The claim-level detail rows behind each disputed line are joined here, one row per claim. The detail comes from the
-- state, keyed on the invoice file, NDC, utilization type and quarter. Each claim row carries the state's reported
-- Rx, fill, pharmacy, date of service and units, which the eligibility layer (int_claim_340b_evidence) has already
-- assessed for 340B evidence.
--
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with disputed_lines as (

    select *
    from {{ ref('int_medicaid_340b_signal') }}
    where has_340b_signal

),

claim_detail as (

    select
        cld.invoice_file,
        cld.state_code,
        cld.manufacturer_code,
        cld.record_id,
        cld.period_covered,
        cld.ndc11,
        cld.rx_number,
        cld.rx_number_normalized,
        cld.fill_number,
        cld.date_of_service,
        cld.date_paid,
        cld.service_provider_npi,
        cld.prescriber_npi,
        cld.units,
        cld.medicaid_amount_reimbursed,
        cld._source_file                                                     as detail_source_file
    from {{ ref('stg_medicaid_claim_level_detail') }} cld

),

evidence as (

    select
        source_record_id,
        evidence_level,
        is_flagged_340b,
        pilot_submissions,
        pilot_ce_340b_ids,
        pilot_statuses,
        purchase_lines,
        purchase_ce_340b_ids,
        pathway_ce_340b_ids,
        observed_route_ce_340b_ids
    from {{ ref('int_claim_340b_evidence') }}
    where source = 'medicaid_cld'

)

select
    -- invoice line identity
    dl.invoice_file,
    dl.line_number,
    dl.manufacturer_code,
    dl.state_code,
    dl.ndc11,
    dl.record_id                                                             as utilization_type_code,
    dl.utilization_type,
    dl.period_covered,
    dl.quarter_start_date,
    dl.quarter_end_date,

    -- invoice line amounts
    dl.ura,
    dl.units_reimbursed,
    dl.rebate_amount_claimed,
    dl.number_of_prescriptions,

    -- signal that triggered the dispute
    dl.signal_submissions,
    dl.signal_units,

    -- claim detail
    cd.rx_number,
    cd.rx_number_normalized,
    cd.fill_number,
    cd.date_of_service,
    cd.date_paid,
    cd.service_provider_npi                                                  as pharmacy_npi,
    cd.prescriber_npi,
    cd.units                                                                 as claim_units,
    cd.medicaid_amount_reimbursed                                            as claim_medicaid_amount,
    cd.detail_source_file,

    -- 340B evidence on the claim (from the shared eligibility layer)
    ev.evidence_level,
    ev.pilot_submissions                                                     as claim_pilot_submissions,
    ev.pilot_ce_340b_ids                                                     as claim_pilot_ce_340b_ids,
    ev.pilot_statuses                                                        as claim_pilot_statuses,
    ev.purchase_lines                                                        as claim_purchase_lines,
    ev.purchase_ce_340b_ids                                                  as claim_purchase_ce_340b_ids,
    ev.pathway_ce_340b_ids                                                   as claim_pathway_ce_340b_ids,
    ev.observed_route_ce_340b_ids                                            as claim_observed_route_ce_340b_ids,

    -- the claim's source_record_id in int_dispensing_claims (an md5 hash)
    ev.source_record_id                                                      as dispensing_claim_id

from disputed_lines dl
join claim_detail cd
    on cd.invoice_file = dl.invoice_file
   and cd.ndc11 = dl.ndc11
   and cd.record_id = dl.record_id
   and cd.period_covered = dl.period_covered
left join evidence ev
    on ev.source_record_id = md5(concat_ws('|', cd.detail_source_file, cd.rx_number,
                                            cast(cd.fill_number as string),
                                            cast(cd.date_of_service as string),
                                            cd.ndc11, cd.service_provider_npi))
