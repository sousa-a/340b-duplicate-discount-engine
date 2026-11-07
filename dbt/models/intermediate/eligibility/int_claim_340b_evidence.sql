-- int_claim_340b_evidence
-- For every MTF and Medicaid claim: what the manufacturer's own data shows about whether it was filled with 340B
-- stock, and for which covered entity. One row per claim. Every piece of evidence is a column with its source, so a
-- reviewer can see exactly why a claim got its level.
--
-- Evidence, strongest first:
--   pilot_*          the same fill was submitted to the 340B rebate Pilot by a covered entity (claim level)
--   is_flagged_340b  the pharmacy flagged the MTF record as 340B (claim level; MTF only)
--   purchase_*       a 340B purchase of the same NDC was shipped to the same pharmacy within
--                    var('purchase_window_days') after the date of service
--   pathway_*        the pharmacy was a registered 340B route for some covered entity on the date of service
--   observed_*       the pharmacy was an observed route (it received 340B shipments for an entity), not registered
--
-- evidence_level, strongest first:
--   claim_level                   a Pilot submission or the pharmacy's own flag
--   pathway_and_purchase          a registered route in force and a 340B purchase for that pharmacy and NDC after the fill
--   observed_route_and_purchase   no registered route, but an observed one, and a 340B purchase for that pharmacy and
--                                 NDC after the fill. Ranked below pathway_and_purchase because the observed route is
--                                 itself built from purchases: the shipments are the only evidence, counted once.
--   pathway_only                  a registered route in force, no purchase found
--   observed_route_only           only an observed route, no purchase for that NDC in the window
--   none                          nothing in the manufacturer's data points to 340B
-- This is not a probability. IQVIA estimates the likelihood that a claim was 340B with eligibility scores built from
-- the prescriber's affiliation and the pharmacy's contract relationships (Sun et al. 2026; Martin and Illich 2022).
-- A manufacturer does not see where a prescription was written, so the engine reports the evidence it can show
-- instead, which is also what an audit or dispute needs.
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

{% set window = var('purchase_window_days') %}

with claims as (

    select * from {{ ref('int_dispensing_claims') }}
    where source in ('mtf', 'medicaid_cld')

),

pilot_links as (

    -- a claim can sit on either side of a match, so both directions are read
    select left_source as source, left_record_id as record_id, right_record_id as submission_id, match_type
    from {{ ref('int_claim_matches') }}
    where right_source = 'pilot' and left_source in ('mtf', 'medicaid_cld')
    union all
    select right_source, right_record_id, left_record_id, match_type
    from {{ ref('int_claim_matches') }}
    where left_source = 'pilot' and right_source in ('mtf', 'medicaid_cld')

),

pilot_evidence as (

    select
        pl.source,
        pl.record_id,
        count(*)                                                          as pilot_submissions,
        count(distinct s.ce_340b_id)                                      as pilot_entities,
        collect_set(s.ce_340b_id)                                         as pilot_ce_340b_ids,
        collect_set(pl.submission_id)                                     as pilot_submission_ids,
        collect_set(r.status)                                             as pilot_statuses,
        collect_set(pl.match_type)                                        as pilot_match_types
    from pilot_links pl
    join {{ ref('stg_pilot_submissions') }} s
        on s.submission_id = pl.submission_id
    left join {{ ref('stg_pilot_rebate_status') }} r
        on r.submission_id = pl.submission_id
    group by pl.source, pl.record_id

),

pathway_evidence as (

    select
        c.source,
        c.source_record_id                                                as record_id,
        count(distinct case when p.pathway_type = 'contract_pharmacy' then p.ce_340b_id end)
                                                                          as contract_pharmacy_entities,
        count(distinct case when p.pathway_type = 'medicaid_ffs_carve_in' then p.ce_340b_id end)
                                                                          as medicaid_carve_in_entities,
        count(distinct case when p.pathway_type = 'observed_340b_ship_to' then p.ce_340b_id end)
                                                                          as observed_route_entities,
        collect_set(case when p.pathway_type <> 'observed_340b_ship_to' then p.ce_340b_id end)
                                                                          as pathway_ce_340b_ids,
        collect_set(case when p.pathway_type = 'observed_340b_ship_to' then p.ce_340b_id end)
                                                                          as observed_route_ce_340b_ids
    from claims c
    join {{ ref('int_340b_pathways') }} p
        on p.pharmacy_npi = c.pharmacy_npi
       and c.date_of_service between p.valid_from and p.valid_to
    group by c.source, c.source_record_id

),

purchase_evidence as (

    select
        c.source,
        c.source_record_id                                                as record_id,
        count(*)                                                          as purchase_lines,
        min(p.invoice_date)                                               as first_purchase_date,
        collect_set(p.ce_340b_id)                                         as purchase_ce_340b_ids
    from claims c
    join {{ ref('int_340b_purchases') }} p
        on p.pharmacy_npi = c.pharmacy_npi
       and p.ndc11 = c.ndc11
       and p.invoice_date between c.date_of_service and date_add(c.date_of_service, {{ window }})
    group by c.source, c.source_record_id

)

select
    c.source,
    c.source_record_id,
    c.manufacturer_code,
    c.payer_channel,
    c.pharmacy_npi,
    c.rx_number_normalized,
    c.fill_number,
    c.ndc11,
    c.date_of_service,
    c.quantity,

    -- claim-level evidence
    coalesce(pe.pilot_submissions, 0)                                     as pilot_submissions,
    coalesce(pe.pilot_entities, 0)                                        as pilot_entities,
    pe.pilot_ce_340b_ids,
    pe.pilot_submission_ids,
    pe.pilot_statuses,
    pe.pilot_match_types,
    coalesce(c.is_flagged_340b, false)                                    as is_flagged_340b,

    -- route and purchase evidence
    coalesce(pw.contract_pharmacy_entities, 0)                            as contract_pharmacy_entities,
    coalesce(pw.medicaid_carve_in_entities, 0)                            as medicaid_carve_in_entities,
    pw.pathway_ce_340b_ids,
    coalesce(pw.observed_route_entities, 0)                               as observed_route_entities,
    pw.observed_route_ce_340b_ids,
    coalesce(pu.purchase_lines, 0)                                        as purchase_lines,
    pu.first_purchase_date,
    pu.purchase_ce_340b_ids,

    case
        when coalesce(pe.pilot_submissions, 0) > 0 or coalesce(c.is_flagged_340b, false) then 'claim_level'
        when coalesce(pw.contract_pharmacy_entities, 0) + coalesce(pw.medicaid_carve_in_entities, 0) > 0 and pu.record_id is not null then 'pathway_and_purchase'
        when coalesce(pw.observed_route_entities, 0) > 0 and pu.record_id is not null then 'observed_route_and_purchase'
        when coalesce(pw.contract_pharmacy_entities, 0) + coalesce(pw.medicaid_carve_in_entities, 0) > 0 then 'pathway_only'
        when coalesce(pw.observed_route_entities, 0) > 0 then 'observed_route_only'
        else 'none'
    end                                                                   as evidence_level,

    c._source_file

from claims c
left join pilot_evidence pe
    on pe.source = c.source and pe.record_id = c.source_record_id
left join pathway_evidence pw
    on pw.source = c.source and pw.record_id = c.source_record_id
left join purchase_evidence pu
    on pu.source = c.source and pu.record_id = c.source_record_id
