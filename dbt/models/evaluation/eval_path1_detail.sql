-- eval_path1_detail
-- Per-row comparison of Path 1 truth against the engine mart. Every row from planted_findings with path = 1 appears
-- here, joined to fct_path1_mfp_340b on evidence_mtf_icn. A missing match means the engine did not produce a row for
-- that MTF claim (should not happen: the mart has one row per non-reversed MTF claim with a payment). Engine rows not
-- in the answer key are false positives if they flag duplicate_evidenced.
--
-- Classification:
--   true_positive       truth says FLAG, engine says duplicate_evidenced
--   false_negative      truth says FLAG, engine says something else (missed duplicate)
--   true_negative       truth says NO_FLAG, engine does not say duplicate_evidenced
--   false_positive_ak   truth says NO_FLAG, engine says duplicate_evidenced (overcall against the answer key)
--
-- Engine rows with finding_status = duplicate_evidenced that have no answer-key row are listed separately in
-- eval_path1_scorecard as false_positive_no_ak (the answer key does not cover every MTF claim, only the situations
-- it planted).
--
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with truth_path1 as (

    select
        cast(finding_id as string)                    as finding_id,
        cast(evidence_mtf_icn as string)              as evidence_mtf_icn,
        cast(path as string)                          as path,
        cast(scenario_code as string)                 as scenario_code,
        cast(expected_verdict as string)              as expected_verdict,
        cast(duplicate_amount as decimal(18, 2))      as truth_duplicate_amount,
        cast(claim_id as string)                      as claim_id,
        cast(drug_key as string)                      as drug_key,
        cast(ndc11 as string)                         as truth_ndc11,
        cast(ce_340b_id as string)                    as ce_340b_id,
        cast(pharmacy_id as string)                   as pharmacy_id,
        cast(tags as string)                          as tags
    from {{ source('truth', 'planted_findings') }}
    where cast(path as string) = '1'

),

engine as (

    select
        mtf_icn,
        finding_status,
        duplicate_amount        as engine_duplicate_amount,
        evidence_level,
        evidence_basis,
        ceiling_per_unit,
        ceiling_source,
        nonduplication_case,
        service_year,
        ndc11,
        manufacturer_code,
        pharmacy_npi
    from {{ ref('fct_path1_mfp_340b') }}

)

select
    t.finding_id,
    t.evidence_mtf_icn,
    t.scenario_code,
    t.expected_verdict,
    t.truth_duplicate_amount,
    t.claim_id,
    t.drug_key,
    t.truth_ndc11,
    t.ce_340b_id,
    t.pharmacy_id,
    t.tags,

    e.finding_status,
    e.engine_duplicate_amount,
    e.evidence_level,
    e.evidence_basis,
    e.ceiling_per_unit,
    e.ceiling_source,
    e.nonduplication_case,
    e.service_year,
    e.ndc11                                                                   as engine_ndc11,
    e.manufacturer_code,
    e.pharmacy_npi,

    case
        when e.mtf_icn is null then 'no_engine_row'
        when t.expected_verdict = 'FLAG' and e.finding_status = 'duplicate_evidenced' then 'true_positive'
        when t.expected_verdict = 'FLAG' and e.finding_status != 'duplicate_evidenced' then 'false_negative'
        when t.expected_verdict != 'FLAG' and e.finding_status = 'duplicate_evidenced' then 'false_positive_ak'
        else 'true_negative'
    end                                                                       as classification,

    -- amount difference when both sides have a number (engine minus truth; negative = engine underestimates)
    case
        when e.mtf_icn is not null and t.truth_duplicate_amount is not null and e.engine_duplicate_amount is not null
            then round(e.engine_duplicate_amount - t.truth_duplicate_amount, 2)
    end                                                                       as amount_difference

from truth_path1 t
left join engine e
    on e.mtf_icn = t.evidence_mtf_icn
