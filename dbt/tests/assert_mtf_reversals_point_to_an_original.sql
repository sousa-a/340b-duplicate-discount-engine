-- A reversal must name the original record it cancels, and that record must be an ORIGINAL.
-- An ORIGINAL must not name another record. Returns the records that break either rule.
{{ config(severity = 'warn') }}
select
    c.mtf_icn,
    c.transaction_code,
    c.mtf_xref_icn,
    o.transaction_code as referenced_transaction_code
from {{ ref('stg_mtf_claims') }} c
left join {{ ref('stg_mtf_claims') }} o
    on o.mtf_icn = c.mtf_xref_icn
where (c.is_reversal and (c.mtf_xref_icn is null or o.transaction_code is distinct from 'ORIGINAL'))
   or (not c.is_reversal and c.mtf_xref_icn is not null)
