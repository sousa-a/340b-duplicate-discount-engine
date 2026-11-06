-- The refund method code and the remark code must agree: code 1 (SDRA) has no remark, code 4 (no refund, ceiling
-- below MFP) has N907 and a zero refund, code 8 (refund of ceiling minus MFP) has N917. Returns the records that
-- break this.
{{ config(severity = 'warn') }}
select mtf_icn, refund_method_code, remark_code, refund_amount
from {{ ref('stg_mtf_payments') }}
where (refund_method_code = '1' and remark_code is not null)
   or (refund_method_code = '4' and (remark_code is distinct from 'N907' or refund_amount <> 0))
   or (refund_method_code = '8' and remark_code is distinct from 'N917')
