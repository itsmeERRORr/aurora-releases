# Aurora Sync Lightroom Classic Plugin

`AuroraSync.lrplugin` imports Aurora pending imports into the Lightroom Classic catalog automatically.

## What It Does

- Watches Aurora pending sync requests.
- Reads the exact import folder written by Aurora.
- Scans that folder only, non-recursively.
- Adds supported RAW files to the active Lightroom Classic catalog.
- Skips files already in the catalog.
- Does not create collections.
- Does not move, delete, or edit files.
- Runs silently while Lightroom Classic is open.

## Install

1. Open Lightroom Classic.
2. Go to `File > Plug-in Manager...`.
3. Remove any older "Aurora Sync" entries first (see Troubleshooting — only ONE may be installed).
4. Click `Add`.
5. Select `lightroom/AuroraSync.lrplugin`.
6. Ensure the plugin status shows **enabled** (green).
7. If the plugin was already installed, remove it and add it again after updating the files.

This is the only plugin. `AuroraSync.lrplugin` is the single source of truth — the old
`AuroraSyncV2`, `AuroraSyncV3Diagnostic`, and `AuroraSyncV4Diagnostic` variants were
removed because they either duplicated the toolkit identifier or were debug stubs that
never imported anything.

## Request Folder

The plugin watches:

```text
~/Library/Application Support/Adobe/Lightroom/commanderonev2/lightroom_sync/pending/
```

Processed requests are moved to:

```text
~/Library/Application Support/Adobe/Lightroom/commanderonev2/lightroom_sync/done/
~/Library/Application Support/Adobe/Lightroom/commanderonev2/lightroom_sync/failed/
```

Logs are written to:

```text
~/Library/Application Support/Adobe/Lightroom/commanderonev2/lightroom_sync/logs/aurora-sync.log
```

## Request JSON

Aurora should write one `.json` file per import:

```json
{
  "id": "7C0E3E58-50D7-42A4-AB68-26C53B4EA1DD",
  "eventName": "FPF Finals 2026",
  "importFolder": "/Events/FPF Finals 2026/RAW",
  "recursive": false,
  "createdAt": "2026-06-12T22:00:00Z"
}
```

`importFolder` must be the exact folder where Aurora moved the files for that import.

## Supported RAW Extensions

`3fr`, `arw`, `cr2`, `cr3`, `dng`, `iiq`, `nef`, `nrw`, `orf`, `raf`, `raw`, `rw2`.

## Troubleshooting

**Lightroom opens after import but nothing gets added to the catalog.**
This means no working plugin is actually running. Check, in order:

1. **Only one Aurora plugin installed and enabled.** In `Plug-in Manager`, there must be
   exactly one entry — "Aurora Sync" — and it must be enabled. Delete any leftover
   diagnostic variants. Multiple plugins sharing a toolkit identifier silently collide.
2. **Confirm the watcher started.** After enabling the plugin (or restarting Lightroom),
   this file must appear:
   ```text
   ~/Library/Application Support/Adobe/Lightroom/commanderonev2/lightroom_sync/logs/aurora-sync.log
   ```
   If it never appears, the plugin's `Init.lua` crashed on load — open the
   `Plug-in Manager` and read the error shown under the plugin.
3. **Never use `os.execute` / `io.popen` in plugin code.** Lightroom's Lua sandbox strips
   these for security; calling them throws `attempt to call field 'execute' (a nil value)`
   and aborts `Init.lua` before the watcher starts. Use the SDK APIs instead
   (`LrFileUtils.createAllDirectories`, `LrTasks`, etc.) — `SyncPendingImports.lua`
   already does.

**How the flow works end to end:**
Aurora writes one `<id>.json` into `…/lightroom_sync/pending/`, then opens Lightroom.
The plugin polls `pending/` every 20 seconds, imports the RAW files from the request's
`importFolder`, and moves the request to `done/` (or `failed/`). So after a fresh import
the catalog updates within ~20 seconds of Lightroom being frontmost.
