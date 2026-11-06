-- stg_manufacturer_codes
-- Code used in file names and EDI envelopes for each manufacturer (MFR001...), with its name. Staging adds nothing
-- but trimming: it is the lookup every other model uses to put a name on a manufacturer code.
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

select
    trim(manufacturer_code)                                          as manufacturer_code,
    trim(manufacturer)                                               as manufacturer_name,
    _source_file,
    _ingested_at
from {{ source('raw', 'manufacturer_codes') }}
