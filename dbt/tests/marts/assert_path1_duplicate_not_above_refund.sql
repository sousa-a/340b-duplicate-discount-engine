-- When the manufacturer paid the full MFP refund (code 1), the duplicate can never exceed the refund: it is the
-- smaller of the two concessions. A row above it means a price or quantity was read wrong. Claims where the
-- manufacturer already applied nonduplication (code 4 or 8) have a reduced refund by design.
select mtf_icn, refund_amount, duplicate_amount
from {{ ref('fct_path1_mfp_340b') }}
where full_mfp_refund_paid
  and duplicate_amount > refund_amount + 0.01
