-- The duplicate can never exceed the MFP refund paid: it is the smaller of the two concessions. A row above it means
-- a price or quantity was read wrong.
select mtf_icn, refund_amount, duplicate_amount
from {{ ref('fct_path1_mfp_340b') }}
where duplicate_amount > refund_amount + 0.01
