-- Each 844 line must claim (WAC - contract price) x quantity, to the cent (SII07 = (SII05 - SII06) x SII03).
-- A difference above half a cent is reported; rounding to cents explains anything smaller.
{{ config(severity = 'warn') }}
select debit_memo_number, line_number, quantity_packages, wac_per_package, contract_price_per_package,
       chargeback_amount,
       (wac_per_package - contract_price_per_package) * quantity_packages as recomputed_amount
from {{ ref('stg_edi_844_chargeback_lines') }}
where abs(chargeback_amount - (wac_per_package - contract_price_per_package) * quantity_packages) > 0.005
