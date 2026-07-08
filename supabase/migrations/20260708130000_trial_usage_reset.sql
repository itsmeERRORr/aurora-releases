-- Hard reset (not the greatest()-based ratchet in trial_usage_bump) used
-- exactly once when a lapsed Pro/Lifetime license grants its device a fresh
-- free trial. See validate-license/index.ts (site_aurora repo) for the
-- eligibility check that gates calling this.
create or replace function public.trial_usage_reset(p_device_hash text)
returns void
language sql
security definer
set search_path = public
as $$
    insert into public.trial_usage (device_hash, used_actions, updated_at)
    values (p_device_hash, 0, now())
    on conflict (device_hash) do update
        set used_actions = 0,
            updated_at = now();
$$;
