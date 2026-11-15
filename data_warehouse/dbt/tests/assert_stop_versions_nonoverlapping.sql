select a.stop_id, a.stop_key as version_a, b.stop_key as version_b
from {{ ref('dim_stop') }} a
join {{ ref('dim_stop') }} b
  on a.stop_id = b.stop_id
 and a.stop_key < b.stop_key
 and a.valid_from < b.valid_to
 and b.valid_from < a.valid_to
