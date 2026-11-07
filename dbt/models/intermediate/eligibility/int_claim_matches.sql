-- int_claim_matches
-- Pairs of records that describe the same fill, across sources, and between Pilot submissions (two covered entities
-- claiming the same fill is the case Path 3 looks for). One row per pair.
--
-- Must be equal: pharmacy NPI, Rx number without leading zeros, fill number, NDC (11 digits).
-- May differ:    date of service, by up to var('date_match_tolerance_days'); quantity, recorded but not required,
--                because some submissions count packages instead of units.
-- match_type says how good the match is: exact, date_shifted, quantity_differs, or date_shifted_quantity_differs.
-- Pairs within one source are left out, except Pilot with Pilot.
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

{% set tolerance = var('date_match_tolerance_days') %}

with claims as (

    select * from {{ ref('int_dispensing_claims') }}
    where pharmacy_npi is not null
      and rx_number_normalized is not null
      and fill_number is not null
      and ndc11 is not null

),

pairs as (

    select
        a.source                                                          as left_source,
        a.source_record_id                                                as left_record_id,
        b.source                                                          as right_source,
        b.source_record_id                                                as right_record_id,
        a.pharmacy_npi,
        a.rx_number_normalized,
        a.fill_number,
        a.ndc11,
        a.date_of_service                                                 as left_date_of_service,
        b.date_of_service                                                 as right_date_of_service,
        abs(datediff(a.date_of_service, b.date_of_service))               as date_difference_days,
        a.quantity                                                        as left_quantity,
        b.quantity                                                        as right_quantity,
        a.ce_340b_id                                                      as left_ce_340b_id,
        b.ce_340b_id                                                      as right_ce_340b_id
    from claims a
    join claims b
        on  a.pharmacy_npi = b.pharmacy_npi
        and a.rx_number_normalized = b.rx_number_normalized
        and a.fill_number = b.fill_number
        and a.ndc11 = b.ndc11
        -- each pair once, in a fixed order
        and (a.source < b.source or (a.source = b.source and a.source_record_id < b.source_record_id))
    where abs(datediff(a.date_of_service, b.date_of_service)) <= {{ tolerance }}
      and (a.source <> b.source or a.source = 'pilot')

)

select
    *,
    case
        when date_difference_days = 0 and left_quantity = right_quantity then 'exact'
        when date_difference_days = 0 then 'quantity_differs'
        when left_quantity = right_quantity then 'date_shifted'
        else 'date_shifted_quantity_differs'
    end                                                                   as match_type
from pairs
