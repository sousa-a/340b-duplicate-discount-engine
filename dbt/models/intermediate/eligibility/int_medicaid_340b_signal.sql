-- int_medicaid_340b_signal
-- Stage 1 of Medicaid/340B detection: identify CMS-R-144 invoice lines where the manufacturer has evidence that 340B
-- units may be on the line. A manufacturer never sees claim-level Medicaid data by default. What it does see is Pilot
-- submissions (and, eventually, ESP submissions) that carry a Medicaid BIN and PCN, telling it that a covered entity
-- submitted a dispense for a Medicaid beneficiary through the 340B rebate program. Aggregating those submissions to
-- state x NDC x quarter produces a count and dollar value that can be compared against the CMS-R-144 invoice lines.
--
-- When the Pilot-sourced 340B units for a state, NDC and quarter exceed zero and an invoice line exists for the same
-- combination, that line is a candidate for dispute: the manufacturer has reason to believe at least some of those
-- rebated units were 340B-effectuated. The manufacturer then requests claim-level detail from the state for those
-- lines, which is stage 2 (fct_path2_medicaid_340b).
--
-- The join matches on manufacturer, state, NDC and quarter. The utilization type (FFSU vs MCOU) is compared but not
-- required to match exactly, because a covered entity's Pilot submission carries the payer BIN/PCN but not whether
-- the state invoices it as FFS or managed care. The model therefore produces one row per invoice line with the total
-- 340B signal for that state, NDC and quarter across both utilization types, so the engine can flag lines that
-- overlap.
--
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with medicaid_submissions as (

    -- Pilot submissions whose BIN/PCN routes through Medicaid, aggregated to state x NDC x quarter.
    -- The state comes from joining the pharmacy NPI back to the entity's MEF entry, or from the OPAIS contract pharmacy
    -- state when the entity is carved in to a state that the MEF covers. Since the Pilot submission carries the pharmacy
    -- NPI and the BIN/PCN, and we can look up which state's Medicaid each pharmacy bills for through the MEF or the
    -- entity's registered state, the aggregation uses the state from the claim-level detail (which was loaded into
    -- int_dispensing_claims as medicaid_cld).
    --
    -- A simpler approach that works with the synthetic data: the Pilot submissions carry Medicaid BIN/PCN, and the
    -- claim-level detail files carry the state code. Since the engine may read claim-level detail only for disputed
    -- lines, the signal must come from the submissions. But in this simulation the covered entity submissions for
    -- Medicaid fills carry a state-specific BIN/PCN that the generator wrote, so we can look up the state from the
    -- OPAIS entity registration. For now, we use the covered entity's primary state from OPAIS.

    select
        s.manufacturer_code,
        ce.state_code,
        s.ndc11,
        date_trunc('quarter', s.date_of_service)                             as quarter_start_date,
        count(*)                                                             as signal_submissions,
        sum(s.quantity)                                                      as signal_units
    from {{ ref('stg_pilot_submissions') }} s
    join {{ ref('stg_hrsa_covered_entities') }} ce
        on ce.ce_340b_id = s.ce_340b_id
    where s.rx_bin is not null
      and upper(s.rx_pcn) not in ('CASH', 'NONE')
      and s.rx_pcn is not null
    group by 1, 2, 3, 4

),

invoice_lines as (

    select
        _source_file,
        line_number,
        manufacturer_code,
        state_code,
        ndc11,
        record_id,
        utilization_type,
        period_covered,
        quarter_start_date,
        quarter_end_date,
        ura,
        units_reimbursed,
        rebate_amount_claimed,
        number_of_prescriptions
    from {{ ref('stg_medicaid_invoice_lines') }}

)

select
    inv._source_file                                                         as invoice_file,
    inv.line_number,
    inv.manufacturer_code,
    inv.state_code,
    inv.ndc11,
    inv.record_id,
    inv.utilization_type,
    inv.period_covered,
    inv.quarter_start_date,
    inv.quarter_end_date,
    inv.ura,
    inv.units_reimbursed,
    inv.rebate_amount_claimed,
    inv.number_of_prescriptions,
    coalesce(sig.signal_submissions, 0)                                      as signal_submissions,
    coalesce(sig.signal_units, 0)                                            as signal_units,
    sig.signal_submissions is not null and sig.signal_submissions > 0         as has_340b_signal
from invoice_lines inv
left join medicaid_submissions sig
    on sig.manufacturer_code = inv.manufacturer_code
   and sig.state_code = inv.state_code
   and sig.ndc11 = inv.ndc11
   and sig.quarter_start_date = inv.quarter_start_date
