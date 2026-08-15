-- Clean up the diagnostic tables used to verify the profile backfill.
drop table if exists public._diag_auth_users;
drop table if exists public._diag_profiles;
