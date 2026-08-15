-- Diagnostic: expose profiles so the backfill can be verified via REST.
-- (Temporary — removed by 0016_drop_diag_tables.sql)
drop table if exists public._diag_profiles;
create table public._diag_profiles as
select uid, username, display_name, lotext_id, is_admin, created_at
from public.profiles;
