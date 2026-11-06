-- A paid submission has a payment date and no denial reason; a denied or rejected one has a reason and no payment.
-- Returns the decisions that break this.
{{ config(severity = 'warn') }}
select submission_id, status, denial_reason, payment_date
from {{ ref('stg_pilot_rebate_status') }}
where (is_paid and (payment_date is null or denial_reason is not null))
   or (not is_paid and (denial_reason is null or payment_date is not null))
