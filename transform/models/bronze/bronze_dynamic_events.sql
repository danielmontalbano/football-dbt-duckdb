-- Bronze: the provider's data, untouched.
-- No renaming, no filtering, no business logic. The only thing we add is
-- provenance: which file each row came from and when we loaded it.
-- If a downstream number looks wrong, this is the layer you compare against
-- the original CSV.

select
    * exclude (filename),
    filename as _source_file,
    current_localtimestamp() as _loaded_at
from {{ source('skillcorner', 'dynamic_events') }}
