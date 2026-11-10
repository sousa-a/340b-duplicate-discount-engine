-- eval_path2_detail
-- Per-row comparison of Path 2 truth against the engine mart. Every row from planted_findings with path = 2 appears
-- here, matched to fct_path2_medicaid_340b through the evidence_invoice_key (state|NDC|quarter|record_id).
--
-- The truth's evidence_invoice_key identifies the CMS-R-144 invoice line. The engine produces one row per claim on a
-- disputed line, so one truth row may match multiple engine rows. This model joins on the invoice key and checks
-- whether the engine flagged at least one claim as duplicate_evidenced on that line.
--
-- For truth FLAG rows, a true positive means the engine found at least one duplicate_evidenced claim on that line.
-- For truth NO_FLAG rows, a false positive means the engine flagged a claim on a line the truth says should not be
-- flagged. The duplicate amount comparison uses the sum of engine duplicate amounts on the line against the truth
-- amount.
--
-- Classification:
--   true_positive       truth says FLAG, engine flagged duplicate_evidenced on the line
--   false_negative      truth says FLAG, engine did not flag the line (no disputed row, or no evidence)
--   true_negative       truth says NO_FLAG, engine did not flag duplicate_evidenced on the line
--   false_positive_ak   truth says NO_FLAG, engine flagged duplicate_evidenced on the line
--   no_engine_row       the invoice line does not appear in the engine mart at all (line was not disputed)
--
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with truth_path2 as (

    select
        cast(finding_id as string)                    as finding_id,
        cast(evidence_invoice_key as string)          as evidence_invoice_key,
        cast(path as string)                          as path,
        cast(scenario_code as string)                 as scenario_code,
        cast(expected_verdict as string)              as expected_verdict,
        cast(duplicate_amount as decimal(18, 2))      as truth_duplicate_amount,
        cast(claim_id as string)                      as claim_id,
        cast(drug_key as string)                      as drug_key,
        cast(ndc11 as string)                         as truth_ndc11,
        cast(ce_340b_id as string)                    as ce_340b_id,
        cast(pharmacy_id as string)                   as pharmacy_id,
        cast(line_of_business as string)              as line_of_business,
        cast(tags as string)                          as tags
    from {{ source('truth', 'planted_findings') }}
    where cast(path as string) = '2'

),

-- Aggregate engine results per invoice line (state|NDC|quarter|record_id)
engine_by_line as (

    select
        concat_ws('|', state_code, ndc11, period_covered, utilization_type_code)
                                                                              as engine_invoice_key,
        sum(case when finding_status = 'duplicate_evidenced' then 1 else 0 end)
                                                                              as flagged_claims,
        count(*)                                                              as total_claims,
        sum(case when finding_status = 'duplicate_evidenced' then duplicate_amount else 0 end)
                                                                              as engine_duplicate_amount,
        max(evidence_level)                                                   as best_evidence_level,
        max(evidence_basis)                                                   as best_evidence_basis,
        max(manufacturer_code)                                                as manufacturer_code,
        max(invoice_file)                                                     as invoice_file
    from {{ ref('fct_path2_medicaid_340b') }}
    group by 1

)

select
    t.finding_id,
    t.evidence_invoice_key,
    t.scenario_code,
    t.expected_verdict,
    t.truth_duplicate_amount,
    t.claim_id,
    t.drug_key,
    t.truth_ndc11,
    t.ce_340b_id,
    t.pharmacy_id,
    t.line_of_business,
    t.tags,

    e.flagged_claims,
    e.total_claims,
    e.engine_duplicate_amount,
    e.best_evidence_level,
    e.best_evidence_basis,
    e.manufacturer_code,
    e.invoice_file,

    case
        when e.engine_invoice_key is null and t.expected_verdict = 'FLAG' then 'false_negative'
        when e.engine_invoice_key is null then 'no_engine_row'
        when t.expected_verdict = 'FLAG' and e.flagged_claims > 0 then 'true_positive'
        when t.expected_verdict = 'FLAG' and e.flagged_claims = 0 then 'false_negative'
        when t.expected_verdict != 'FLAG' and e.flagged_claims > 0 then 'false_positive_ak'
        else 'true_negative'
    end                                                                      as classification,

    case
        when e.engine_invoice_key is not null and t.truth_duplicate_amount is not null
             and e.engine_duplicate_amount is not null
            then round(e.engine_duplicate_amount - t.truth_duplicate_amount, 2)
    end                                                                       as amount_difference

from truth_path2 t
left join engine_by_line e
    on e.engine_invoice_key = t.evidence_invoice_key
