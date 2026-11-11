-- Staging: every dynamic event, as delivered.
-- No filtering, no business logic. The provider's column names are already
-- snake_case, so nothing is renamed either. The only thing added is
-- provenance: which file each row came from and when it was loaded.
-- If a downstream number looks wrong, this is the model you compare against
-- the original CSV.

select
    * exclude (filename),
    filename as _source_file,
    current_localtimestamp() as _loaded_at
from {{ source('skillcorner', 'dynamic_events') }}
