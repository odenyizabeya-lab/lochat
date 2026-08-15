-- Diagnostic: expose auth users so the count can be verified via the REST API.
-- (Temporary — removed by 0015_drop_diag_auth_users.sql)
drop table if exists public._diag_auth_users;
create table public._diag_auth_users as
select id, email, email_confirmed_at is not null as confirmed, created_at
from auth.users;
