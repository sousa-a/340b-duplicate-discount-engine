-- Claim-level detail must support the invoice: for each invoice file, NDC and utilization type, the units of the
-- detail claims must add up to the units on the invoice line. A difference is a unit the state invoiced without a
-- claim behind it, or the other way around. Returns the lines that do not match.
{{ config(severity = 'warn') }}
with detail as (
    select invoice_file, ndc11, record_id, count(*) as claims, sum(units) as detail_units
    from {{ ref('stg_medicaid_claim_level_detail') }}
    group by invoice_file, ndc11, record_id
)
select i._source_file as invoice_file, i.ndc11, i.record_id, i.units_reimbursed, d.detail_units, d.claims
from {{ ref('stg_medicaid_invoice_lines') }} i
full outer join detail d
    on d.invoice_file = i._source_file and d.ndc11 = i.ndc11 and d.record_id = i.record_id
where i.units_reimbursed is distinct from d.detail_units
