-- eval_path3_detail
-- Per-row comparison of Path 3 truth against the engine mart. Every row from planted_findings with path = 3 appears
-- here, matched to fct_path3_same_fill_diversion on pilot_submission_id.
--
-- The truth marks one submission per same-fill pair as FLAG (the "second" entity's claim). The mart produces two rows
-- per pair (one per submission). The eval joins on pilot_submission_id to find whether the truth's flagged submission
-- appears in the mart.
--
-- Classification (corrected pattern from Path 2 validation):
--   false_negative      truth says FLAG, engine has no row for this submission (must come before no_engine_row)
--   no_engine_row       truth says NO_FLAG (or no verdict) and engine has no row (no pair detected)
--   true_positive       truth says FLAG, engine says duplicate_evidenced
--   false_negative      truth says FLAG, engine says no_rebate_paid (pair found but rebate not paid)
--   true_negative       truth says NO_FLAG, engine does not say duplicate_evidenced
--   false_positive_ak   truth says NO_FLAG, engine says duplicate_evidenced
--
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with truth_path3 as (

    select
        cast(finding_id as string)                          as finding_id,
        cast(evidence_pilot_submission_id as string)        as pilot_submission_id,
        cast(evidence_chargeback_sale_line_id as string) as chargeback_line_key,
        cast(path as string)                                as path,
        cast(scenario_code as string)                       as scenario_code,
        cast(expected_verdict as string)                    as expected_verdict,
        cast(duplicate_amount as decimal(18, 2))            as truth_duplicate_amount,
        cast(tags as string)                                as tags
    from {{ source('truth', 'planted_findings') }}
    where cast(path as string) = '3'

),

engine as (

    select
        pilot_submission_id,
        ce_340b_id,
        paired_ce_340b_id,
        paired_pilot_submission_id,
        pharmacy_npi,
        ndc11,
        date_of_service,
        match_type,
        rebate_status,
        rebate_amount,
        finding_status,
        duplicate_amount                              as engine_duplicate_amount,
        rules_channel,
        manufacturer_code
    from {{ ref('fct_path3_same_fill_diversion') }}

)

select
    t.finding_id,
    t.pilot_submission_id,
    t.chargeback_sale_line_id,
    t.scenario_code,
    t.expected_verdict,
    t.truth_duplicate_amount,
    t.tags,

    e.ce_340b_id,
    e.paired_ce_340b_id,
    e.paired_pilot_submission_id,
    e.pharmacy_npi,
    e.ndc11,
    e.date_of_service,
    e.match_type,
    e.rebate_status,
    e.rebate_amount,
    e.finding_status,
    e.engine_duplicate_amount,
    e.rules_channel,
    e.manufacturer_code,

    -- Corrected classification: FLAG rows with no engine match are false_negative, not no_engine_row.
    -- This prevents the recall inflation bug found in Path 2 validation.
    case
        when e.pilot_submission_id is null and t.expected_verdict = 'FLAG' then 'false_negative'
        when e.pilot_submission_id is null then 'no_engine_row'
        when t.expected_verdict = 'FLAG' and e.finding_status = 'duplicate_evidenced' then 'true_positive'
        when t.expected_verdict = 'FLAG' and e.finding_status != 'duplicate_evidenced' then 'false_negative'
        when t.expected_verdict != 'FLAG' and e.finding_status = 'duplicate_evidenced' then 'false_positive_ak'
        else 'true_negative'
    end                                                                       as classification,

    case
        when e.pilot_submission_id is not null and t.truth_duplicate_amount is not null
             and e.engine_duplicate_amount is not null
            then round(e.engine_duplicate_amount - t.truth_duplicate_amount, 2)
    end                                                                       as amount_difference

from truth_path3 t
left join engine e
    on e.pilot_submission_id = t.pilot_submission_id
