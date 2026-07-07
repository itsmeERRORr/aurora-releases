-- Server-side free-trial counter, keyed by the hashed device id (never the raw UUID).
create table if not exists public.trial_usage (
    device_hash  text primary key,
    used_actions integer not null default 0,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

-- RLS on, with NO anon policies: the table is only ever read/written by the
-- `trial-sync` Edge Function using the service-role key. The anon client can't
-- touch it directly (so it can't reset its own count via the REST API).
alter table public.trial_usage enable row level security;

-- Atomic "raise to the max" upsert in a single statement (no read-modify-write
-- race): inserts the row or bumps used_actions up to greatest(existing, incoming),
-- and returns the resulting value. Called by the trial-sync Edge Function.
create or replace function public.trial_usage_bump(p_device_hash text, p_used integer)
returns integer
language sql
security definer
set search_path = public
as $$
    insert into public.trial_usage (device_hash, used_actions)
    values (p_device_hash, p_used)
    on conflict (device_hash) do update
        set used_actions = greatest(public.trial_usage.used_actions, excluded.used_actions),
            updated_at = now()
    returning used_actions;
$$;
