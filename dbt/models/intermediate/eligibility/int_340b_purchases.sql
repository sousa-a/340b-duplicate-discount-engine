-- int_340b_purchases
-- 340B purchases the manufacturer knows about: chargeback lines from the EDI 844 files, minus the lines it disputed.
-- One row per chargeback line. Each line is a sale to a covered entity's 340B account, shipped to a pharmacy.
--
-- The 844 names the ship-to pharmacy by name and DEA number, while dispensing claims use the pharmacy NPI. The link is
-- made by name against the OPAIS contract pharmacy list, the only public file with both a pharmacy name and an NPI.
-- Entity-owned pharmacies are not in that list, so their purchases keep pharmacy_npi NULL and
-- pharmacy_link_method 'unlinked'; they count in the totals but cannot support a claim.
--
-- Quantities are packages, as the 844 sends them. Claims count units, and no inbox file gives units per package, so
-- this layer checks that a purchase exists for a claim, not how many units it covers.
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

with pharmacy_names as (

    select distinct pharmacy_name, pharmacy_npi
    from {{ ref('stg_hrsa_contract_pharmacies') }}

),

lines as (

    select l.*
    from {{ ref('stg_edi_844_chargeback_lines') }} l
    left anti join {{ ref('stg_chargeback_disputes') }} d
        on d.sale_line_id = l.sale_line_id

)

select
    l.sale_line_id,
    l.debit_memo_number,
    l.manufacturer_code,
    l.wholesaler_id,
    l.customer_340b_id                                                    as ce_340b_id,
    l.ship_to_name,
    l.ship_to_dea,
    n.pharmacy_npi,
    case when n.pharmacy_npi is not null then 'opais_contract_pharmacy_name' else 'unlinked' end
                                                                          as pharmacy_link_method,
    l.ndc11,
    l.invoice_number,
    l.invoice_date,
    l.quantity_packages,
    l.contract_price_per_package,
    l.wac_per_package,
    l.chargeback_amount,
    l._source_file
from lines l
left join pharmacy_names n
    on n.pharmacy_name = l.ship_to_name
