-- eval_path3_scorecard
-- Aggregate evaluation metrics for Path 3. One section per scenario code, plus an ALL row and a row for engine flags
-- that have no answer-key entry (false_positive_no_ak). Same structure as eval_path1_scorecard and
-- eval_path2_scorecard.
--
-- Key metrics:
--   precision = TP / (TP + FP)         of the submissions the engine flagged, how many are true same-fill duplicates
--   recall    = TP / (TP + FN)         of the true same-fill duplicates, how many the engine found
--   f1        = 2 * P * R / (P + R)    harmonic mean
--   amount_captured_pct                share of the true duplicate dollars the engine's flags account for
--
-- The FP count has two parts:
--   false_positive_ak    engine flagged, answer key says NO_FLAG
--   false_positive_no_ak engine flagged duplicate_evidenced on a submission not in the answer key at all
--
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with detail as (

    select * from {{ ref('eval_path3_detail') }}

),

-- engine-flagged submissions not in the answer key
engine_flagged as (

    select
        pilot_submission_id,
        duplicate_amount
    from {{ ref('fct_path3_same_fill_diversion') }}
    where finding_status = 'duplicate_evidenced'

),

engine_flags_no_ak as (

    select
        ef.pilot_submission_id,
        ef.duplicate_amount
    from engine_flagged ef
    left join {{ source('truth', 'planted_findings') }} t
        on cast(t.pilot_submission_id as string) = ef.pilot_submission_id
       and cast(t.path as string) = '3'
    where t.pilot_submission_id is null

),

-- per-scenario counts from the answer-key join
by_scenario as (

    select
        scenario_code,
        count(*)                                                              as truth_rows,
        sum(case when expected_verdict = 'FLAG' then 1 else 0 end)           as truth_flags,
        sum(case when classification = 'true_positive' then 1 else 0 end)    as tp,
        sum(case when classification = 'false_negative' then 1 else 0 end)   as fn,
        sum(case when classification = 'false_positive_ak' then 1 else 0 end) as fp_ak,
        sum(case when classification = 'true_negative' then 1 else 0 end)    as tn,
        sum(case when classification = 'no_engine_row' then 1 else 0 end)    as no_engine_row,
        sum(case when classification = 'true_positive' then engine_duplicate_amount else 0 end)
                                                                              as tp_engine_amount,
        sum(case when classification = 'true_positive' then truth_duplicate_amount else 0 end)
                                                                              as tp_truth_amount,
        sum(case when expected_verdict = 'FLAG' then truth_duplicate_amount else 0 end)
                                                                              as total_truth_amount,
        sum(case when classification = 'false_negative' then truth_duplicate_amount else 0 end)
                                                                              as fn_truth_amount
    from detail
    group by scenario_code

),

no_ak_row as (

    select
        'NO_AK_FLAG' as scenario_code,
        cast(0 as bigint) as truth_rows,
        cast(0 as bigint) as truth_flags,
        cast(0 as bigint) as tp,
        cast(0 as bigint) as fn,
        count(*)           as fp_ak,
        cast(0 as bigint) as tn,
        cast(0 as bigint) as no_engine_row,
        cast(0 as decimal(18, 2)) as tp_engine_amount,
        cast(0 as decimal(18, 2)) as tp_truth_amount,
        cast(0 as decimal(18, 2)) as total_truth_amount,
        cast(0 as decimal(18, 2)) as fn_truth_amount
    from engine_flags_no_ak

),

all_row as (

    select
        'ALL' as scenario_code,
        s.truth_rows,
        s.truth_flags,
        s.tp,
        s.fn,
        s.fp_ak + n.fp_no_ak                                                 as fp_ak,
        s.tn,
        s.no_engine_row,
        s.tp_engine_amount,
        s.tp_truth_amount,
        s.total_truth_amount,
        s.fn_truth_amount
    from (
        select
            sum(truth_rows) as truth_rows,
            sum(truth_flags) as truth_flags,
            sum(tp) as tp,
            sum(fn) as fn,
            sum(fp_ak) as fp_ak,
            sum(tn) as tn,
            sum(no_engine_row) as no_engine_row,
            sum(tp_engine_amount) as tp_engine_amount,
            sum(tp_truth_amount) as tp_truth_amount,
            sum(total_truth_amount) as total_truth_amount,
            sum(fn_truth_amount) as fn_truth_amount
        from by_scenario
    ) s
    cross join (
        select count(*) as fp_no_ak from engine_flags_no_ak
    ) n

),

combined as (

    select * from by_scenario
    union all
    select * from all_row
    union all
    select * from no_ak_row

)

select
    scenario_code,
    truth_rows,
    truth_flags,
    tp,
    fn,
    fp_ak,
    tn,
    no_engine_row,

    fp_ak                                                                     as fp,

    case when tp + fp_ak > 0
         then round(cast(tp as decimal(18, 6)) / (tp + fp_ak), 4)
    end                                                                       as precision,

    case when tp + fn > 0
         then round(cast(tp as decimal(18, 6)) / (tp + fn), 4)
    end                                                                       as recall,

    case when tp + fp_ak > 0 and tp + fn > 0 and tp > 0
         then round(
             2.0 * (cast(tp as decimal(18, 6)) / (tp + fp_ak))
                 * (cast(tp as decimal(18, 6)) / (tp + fn))
             / ((cast(tp as decimal(18, 6)) / (tp + fp_ak))
                 + (cast(tp as decimal(18, 6)) / (tp + fn)))
         , 4)
    end                                                                       as f1,

    tp_engine_amount,
    tp_truth_amount,
    total_truth_amount,
    fn_truth_amount,

    case when total_truth_amount > 0
         then round(tp_truth_amount / total_truth_amount, 4)
    end                                                                       as amount_captured_pct

from combined

order by
    case scenario_code when 'ALL' then 0 when 'NO_AK_FLAG' then 2 else 1 end,
    scenario_code
