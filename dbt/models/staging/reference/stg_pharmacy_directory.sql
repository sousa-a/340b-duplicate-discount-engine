-- stg_pharmacy_directory
-- One row per pharmacy: NPI, DEA number, name and state. The file is a synthetic stand-in for the licensed pharmacy
-- directories manufacturers use to cross-reference the DEA numbers on wholesaler files (844, 867) with the NPIs on
-- dispensing claims (MTF, Medicaid, Pilot). It says nothing about 340B: ownership and contract arrangements come
-- from OPAIS, not from a directory.
-- All data is synthetic (SYNTHETIC_DATA_NOTICE.md).

select
    trim(pharmacy_npi)                                               as pharmacy_npi,
    upper(trim(dea_number))                                          as dea_number,
    trim(pharmacy_name)                                              as pharmacy_name,
    trim(state_code)                                                 as state_code,
    _source_file,
    _ingested_at
from {{ source('raw', 'pharmacy_directory') }}
