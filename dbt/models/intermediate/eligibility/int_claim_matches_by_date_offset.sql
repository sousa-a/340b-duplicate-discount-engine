-- int_claim_matches_by_date_offset
-- How many matches each day of difference in date of service contributes, per pair of sources. It shows what the
-- tolerance var('date_match_tolerance_days') is buying: if the counts fall to zero after a few days, a wider window
-- adds nothing; if they stay high, the window may be catching different fills.
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

select
    left_source,
    right_source,
    date_difference_days,
    count(*)                                                              as matches,
    sum(case when left_quantity = right_quantity then 0 else 1 end)       as matches_with_quantity_difference
from {{ ref('int_claim_matches') }}
group by left_source, right_source, date_difference_days
