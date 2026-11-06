-- stg_pilot_ceiling_prices
-- The manufacturer's quarterly WAC and 340B ceiling price per package for Pilot drugs, one row per NDC and quarter.
-- year_quarter arrives as text (2027Q1); the first and last day of the quarter are added so later models can join
-- on a date of service with a simple between.
--
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with source as (

    select * from {{ source('raw', 'pilot_ceiling_prices') }}

),

typed as (

    select
        regexp_extract(_source_file, 'MFR[0-9]{3}', 0)              as manufacturer_code,
        ndc11,
        year_quarter,
        -- guarded by the pattern: with ANSI SQL on, make_date fails the whole query on an impossible month (Q5)
        case when year_quarter rlike '^[0-9]{4}Q[1-4]$' then make_date(
            cast(substr(year_quarter, 1, 4) as int),
            (cast(substr(year_quarter, 6, 1) as int) - 1) * 3 + 1,
            1
        ) end                                                        as quarter_start_date,
        try_cast(package_days as decimal(10, 2))                     as package_days,
        try_cast(wac_per_package as decimal(18, 2))                  as wac_per_package,
        try_cast(ceiling_price_per_package as decimal(18, 2))        as ceiling_price_per_package,

        _source_file,
        _ingested_at

    from source

)

select
    *,
    last_day(add_months(quarter_start_date, 2))                      as quarter_end_date
from typed
