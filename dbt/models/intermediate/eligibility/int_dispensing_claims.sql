-- int_dispensing_claims
-- Every dispensing claim the manufacturer receives, from three sources, in one shape so they can be matched:
--   mtf           Medicare Part D claims of MFP drugs from the Medicare Transaction Facilitator (originals that were
--                 not reversed; a reversed claim was cancelled and is owed nothing)
--   medicaid_cld  Medicaid claims from state claim-level detail behind CMS-R-144 invoices
--   pilot         claims covered entities submitted to the 340B rebate Pilot
-- Each row keeps the source and the source's own identifier, so every later finding can be traced back.
-- The fill is identified by pharmacy NPI, Rx number (without leading zeros), fill number and NDC; date of service
-- and quantity are compared, not required to be equal (int_claim_matches).
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with mtf as (

    select
        'mtf'                                                             as source,
        c.mtf_icn                                                         as source_record_id,
        regexp_extract(c._source_file, 'MFR[0-9]{3}', 0)                 as manufacturer_code,
        'medicare_part_d'                                                 as payer_channel,
        c.service_provider_id                                             as pharmacy_npi,
        nullif(regexp_replace(c.rx_number, '^0+', ''), '')                as rx_number_normalized,
        c.fill_number,
        c.ndc11,
        c.date_of_service,
        c.quantity_dispensed                                              as quantity,
        cast(null as string)                                              as ce_340b_id,
        c.is_flagged_340b,
        c._source_file
    from {{ ref('stg_mtf_claims') }} c
    left anti join {{ ref('stg_mtf_claims') }} r
        on r.mtf_xref_icn = c.mtf_icn
    where not c.is_reversal

),

medicaid as (

    select
        'medicaid_cld'                                                    as source,
        md5(concat_ws('|', _source_file, rx_number, cast(fill_number as string), cast(date_of_service as string),
                      ndc11, service_provider_npi))                       as source_record_id,
        manufacturer_code,
        case record_id when 'FFSU' then 'medicaid_ffs' when 'MCOU' then 'medicaid_mco' end as payer_channel,
        service_provider_npi                                              as pharmacy_npi,
        rx_number_normalized,
        fill_number,
        ndc11,
        date_of_service,
        units                                                             as quantity,
        cast(null as string)                                              as ce_340b_id,
        cast(null as boolean)                                             as is_flagged_340b,
        _source_file
    from {{ ref('stg_medicaid_claim_level_detail') }}

),

pilot as (

    select
        'pilot'                                                           as source,
        submission_id                                                     as source_record_id,
        manufacturer_code,
        'pilot_submission'                                                as payer_channel,
        service_provider_npi                                              as pharmacy_npi,
        rx_number_normalized,
        fill_number,
        ndc11,
        date_of_service,
        quantity,
        ce_340b_id,
        cast(null as boolean)                                             as is_flagged_340b,
        _source_file
    from {{ ref('stg_pilot_submissions') }}

)

select * from mtf
union all
select * from medicaid
union all
select * from pilot
