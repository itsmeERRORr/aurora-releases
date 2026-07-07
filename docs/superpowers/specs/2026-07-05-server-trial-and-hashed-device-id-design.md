# Server-Synced Trial + Hashed Device ID — Design

**Goal:** Move the 5-action free-trial counter from a purely local file to Supabase (so it can't be reset by deleting a local file), while never sending the raw hardware UUID to the server. The same hashed device identifier also replaces the raw UUID in license activation.

## Decisions (settled with owner)

- **Device identity:** `deviceHash = SHA256(hardwareUUID + pepper)`, hex. One shared function used by both trial and license. Server never receives/stores the raw UUID.
- **Trial model:** local counter + server sync (offline-tolerant). Offline imports are allowed; the server is the source of truth and corrects the count on the next online sync.
- **License:** send the hash in place of `mac_uuid`. No server logic change needed (the function treats `mac_uuid` as an opaque string). Existing bindings for the 2 real activations must be reset server-side so the new hash can bind.

## Device hash

`SHA256(uuid + "|" + pepper)`, hex-encoded. The pepper lives in the client binary — it makes the hash app-specific and stops trivial cross-app correlation, but is not an anti-cheat mechanism (privacy only). A macOS `IOPlatformUUID` has ~122 bits of entropy, so the hash is not brute-forceable back to the UUID.

## Trial sync protocol

Local `trial_state.json` (HMAC-signed, as today) remains the offline cache. The server holds the authoritative count.

- **Reconciliation rule:** effective count = `max(local, server)`, applied on both ends. A forged low server response can't lower the local count; a forged high one only hurts the attacker. So the sync response needs no signature.
- **On consume** (import / added folder): increment local immediately (works offline), then fire-and-forget a push to the server.
- **On launch** (online, non-blocking): sync to pull the server max — this is what corrects a deleted/edited local file back up to the server's count.
- `canUseTrialAction` reads the local count, so imports work offline.

**Residual gap (accepted):** a user who stays fully offline and hand-edits the local file (defeating the HMAC via the in-binary pepper) can exceed 5 until they next connect. Bounded and irrelevant for a 5-action trial; this is the inherent cost of offline tolerance the owner chose.

### Edge Function `trial-sync`

Input `{ device_hash, used_actions }`. Uses the service-role key (RLS blocks direct anon writes). Atomic upsert:

```sql
insert into trial_usage (device_hash, used_actions)
values ($1, $2)
on conflict (device_hash)
do update set used_actions = greatest(trial_usage.used_actions, excluded.used_actions),
              updated_at = now()
returning used_actions;
```

Returns `{ used_actions }`. Client sets `local = max(local, returned)`.

### Table + RLS

`trial_usage(device_hash text primary key, used_actions int not null default 0, created_at, updated_at)`. RLS enabled, no anon policies — only the Edge Function (service role) writes/reads.

## Client changes

- `DeviceIdentity.deviceHash()` — new shared helper.
- `LicensingService`: `activate`, `isActivated`, `cancelSubscription` use `deviceHash()` instead of `hardwareUUID()`. Signed-message flow unchanged (hash flows through as the `uuid` field).
- `TrialSyncService.sync(localUsed:)` — calls the Edge Function.
- `AppState.syncTrialUsage()` — reconciles; called at launch (online) and after each consume.

## Migration of the 2 existing activations

After deploy: null the bound device on the 2 license rows. Each app self-heals on the next online launch (revalidation sends the hash, server re-binds it). Re-entering the key forces it immediately.
