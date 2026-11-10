-- fct_path3_same_fill_diversion
-- Path 3, same-fill diversion. One row per Pilot submission that is part of a same-fill pair: two different covered
-- entities submitted the same dispensed fill to the 340B Pilot. The platform catches exact-match duplicates and rejects
-- the second submission (Sun et al. 2026). The engine catches fuzzy matches the platform missed (reformatted Rx number
-- from the noise layer, shifted date of service) and flags both submissions in the pair for audit.
--
-- Detection: int_claim_matches produces Pilot-to-Pilot pairs where both sides match on pharmacy NPI, normalized Rx
-- number, fill number and NDC-11, but the covered entity differs. Each pair is unpivoted into two rows so the grain
-- is one row per submission. The duplicate_amount is the rebate paid on the submission (from the Pilot rebate status).
-- When both submissions are paid, two concessions were given on one fill; one of them is the duplicate.
--
-- finding_status:
--   duplicate_evidenced    this submission is part of a confirmed same-fill pair with a different entity
--   no_rebate_paid         the submission is part of a pair but no rebate was paid (denied or rejected by the platform)
--
-- rules_channel:
--   pilot_same_fill_ground    the Pilot's "rebate already provided to another entity" denial ground (Nikpay et al. 2024)
--   hrsa_audit                referral to HRSA when the pair involves a non-Pilot chargeback or a denied submission
--
-- The finding is evidence for an audit or HRSA referral. The engine does not determine which entity's claim is
-- legitimate; that is resolved during dispute.
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with same_fill_pairs as (

    -- Pilot-to-Pilot pairs where two different covered entities submitted the same fill.
    -- int_claim_matches already guarantees: same pharmacy NPI, normalized Rx number, fill number, NDC-11,
    -- date of service within tolerance. The filter left_source = right_source = 'pilot' with different entities
    -- is the Path 3 signal.
    select
        left_record_id                                                        as left_submission_id,
        right_record_id                                                       as right_submission_id,
        left_ce_340b_id,
        right_ce_340b_id,
        pharmacy_npi,
        rx_number_normalized,
        fill_number,
        ndc11,
        left_date_of_service,
        right_date_of_service,
        date_difference_days,
        left_quantity,
        right_quantity,
        match_type
    from {{ ref('int_claim_matches') }}
    where left_source = 'pilot'
      and right_source = 'pilot'
      and left_ce_340b_id != right_ce_340b_id

),

-- Unpivot: one row per submission in the pair. Each submission carries its own entity, rebate status and amount,
-- plus the paired entity's ID and submission ID for reference.
unpivoted as (

    select
        left_submission_id                                                    as pilot_submission_id,
        left_ce_340b_id                                                       as ce_340b_id,
        right_ce_340b_id                                                      as paired_ce_340b_id,
        right_submission_id                                                   as paired_pilot_submission_id,
        pharmacy_npi,
        rx_number_normalized,
        fill_number,
        ndc11,
        left_date_of_service                                                  as date_of_service,
        left_quantity                                                         as quantity,
        match_type,
        date_difference_days
    from same_fill_pairs

    union all

    select
        right_submission_id                                                   as pilot_submission_id,
        right_ce_340b_id                                                      as ce_340b_id,
        left_ce_340b_id                                                       as paired_ce_340b_id,
        left_submission_id                                                    as paired_pilot_submission_id,
        pharmacy_npi,
        rx_number_normalized,
        fill_number,
        ndc11,
        right_date_of_service                                                 as date_of_service,
        right_quantity                                                        as quantity,
        match_type,
        date_difference_days
    from same_fill_pairs

),

-- Join rebate status for each submission
with_rebate as (

    select
        u.*,
        s.manufacturer_code,
        s.rx_bin,
        s.rx_pcn,
        r.status                                                              as rebate_status,
        coalesce(r.rebate_amount, 0)                                          as rebate_amount
    from unpivoted u
    join {{ ref('stg_pilot_submissions') }} s
        on s.submission_id = u.pilot_submission_id
    left join {{ ref('stg_pilot_rebate_status') }} r
        on r.submission_id = u.pilot_submission_id

),

-- Also pull the paired submission's rebate status for context
with_paired_rebate as (

    select
        w.*,
        pr.status                                                             as paired_rebate_status,
        coalesce(pr.rebate_amount, 0)                                         as paired_rebate_amount
    from with_rebate w
    left join {{ ref('stg_pilot_rebate_status') }} pr
        on pr.submission_id = w.paired_pilot_submission_id

)

select
    -- submission identity
    cast(pilot_submission_id as string)                                       as pilot_submission_id,
    cast(ce_340b_id as string)                                                as ce_340b_id,
    cast(paired_ce_340b_id as string)                                         as paired_ce_340b_id,
    cast(paired_pilot_submission_id as string)                                as paired_pilot_submission_id,

    -- the fill
    cast(pharmacy_npi as string)                                              as pharmacy_npi,
    cast(rx_number_normalized as string)                                      as rx_number_normalized,
    cast(fill_number as int)                                                  as fill_number,
    cast(ndc11 as string)                                                     as ndc11,
    cast(date_of_service as date)                                             as date_of_service,
    cast(quantity as decimal(14, 3))                                          as quantity,
    cast(manufacturer_code as string)                                         as manufacturer_code,

    -- match quality
    cast(match_type as string)                                                as match_type,
    cast(date_difference_days as int)                                         as date_difference_days,

    -- rebate on this submission
    cast(rebate_status as string)                                             as rebate_status,
    cast(rebate_amount as decimal(18, 2))                                     as rebate_amount,

    -- rebate on the paired submission (context for audit)
    cast(paired_rebate_status as string)                                      as paired_rebate_status,
    cast(paired_rebate_amount as decimal(18, 2))                              as paired_rebate_amount,

    -- the finding
    cast(case
        when rebate_status = 'PAID' then 'duplicate_evidenced'
        else 'no_rebate_paid'
    end as string)                                                            as finding_status,

    -- duplicate amount: the rebate paid on this submission, which is one of two concessions on the same fill
    cast(case
        when rebate_status = 'PAID' then rebate_amount
    end as decimal(18, 2))                                                    as duplicate_amount,

    -- resolution channel
    cast(case
        when rebate_status = 'PAID' then 'pilot_same_fill_ground'
        else 'hrsa_audit'
    end as string)                                                            as rules_channel,

    -- which datasets the finding rests on
    cast(array('pilot_submissions', 'pilot_rebate_status') as array<string>)  as datasets_used

from with_paired_rebate
