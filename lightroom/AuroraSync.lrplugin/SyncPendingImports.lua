local LrApplication = import "LrApplication"
local LrFileUtils = import "LrFileUtils"
local LrPathUtils = import "LrPathUtils"
local LrTasks = import "LrTasks"

local SyncPendingImports = {}

local CHECK_INTERVAL_SECONDS = 6
local SUPPORTED_RAW_EXTENSIONS = {
    ["3fr"] = true,
    arw = true,
    cr2 = true,
    cr3 = true,
    dng = true,
    iiq = true,
    nef = true,
    nrw = true,
    orf = true,
    raf = true,
    raw = true,
    rw2 = true,
}

local function path_child(parent, child)
    return LrPathUtils.child(parent, child)
end

-- Build the exact path the Aurora macOS app writes to, derived from the user's
-- home folder. Do NOT use getStandardFilePath("appData") — on recent Lightroom
-- Classic versions it does not resolve to ~/Library/Application Support/Adobe/
-- Lightroom, which silently breaks the watcher (wrong/empty pending folder).
local function sync_root()
    local home = LrPathUtils.getStandardFilePath("home")
    local p = path_child(home, "Library")
    p = path_child(p, "Application Support")
    p = path_child(p, "Adobe")
    p = path_child(p, "Lightroom")
    p = path_child(p, "commanderonev2")
    p = path_child(p, "lightroom_sync")
    return p
end

local function paths()
    local root = sync_root()
    return {
        root = root,
        pending = path_child(root, "pending"),
        processing = path_child(root, "processing"),
        done = path_child(root, "done"),
        failed = path_child(root, "failed"),
        logs = path_child(root, "logs"),
    }
end

local function ensure_directories()
    local p = paths()
    LrFileUtils.createAllDirectories(p.pending)
    LrFileUtils.createAllDirectories(p.processing)
    LrFileUtils.createAllDirectories(p.done)
    LrFileUtils.createAllDirectories(p.failed)
    LrFileUtils.createAllDirectories(p.logs)
    return p
end

local function now_stamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

local function log_line(message)
    local p = ensure_directories()
    local log_path = path_child(p.logs, "aurora-sync.log")
    local file = io.open(log_path, "a")
    if file then
        file:write("[" .. now_stamp() .. "] " .. tostring(message) .. "\n")
        file:close()
    end
end

local function read_text(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    return text
end

local function write_text(path, text)
    local file = io.open(path, "w")
    if not file then return false end
    file:write(text)
    file:close()
    return true
end

local function unescape_json_string(value)
    value = string.gsub(value, "\\/", "/")
    value = string.gsub(value, '\\"', '"')
    value = string.gsub(value, "\\n", "\n")
    value = string.gsub(value, "\\r", "\r")
    value = string.gsub(value, "\\t", "\t")
    value = string.gsub(value, "\\\\", "\\")
    return value
end

local function json_string_field(text, key)
    local pattern = '"' .. key .. '"%s*:%s*"(.-)"'
    local value = string.match(text, pattern)
    if value then return unescape_json_string(value) end
    return nil
end

local function json_boolean_field(text, key)
    local pattern = '"' .. key .. '"%s*:%s*(%a+)'
    local value = string.match(text, pattern)
    if value == "true" then return true end
    if value == "false" then return false end
    return nil
end

local function json_escape(value)
    value = tostring(value or "")
    value = string.gsub(value, "\\", "\\\\")
    value = string.gsub(value, '"', '\\"')
    value = string.gsub(value, "\n", "\\n")
    value = string.gsub(value, "\r", "\\r")
    value = string.gsub(value, "\t", "\\t")
    return value
end

local function basename(path)
    return LrPathUtils.leafName(path)
end

local function move_request(source, target_directory)
    local target = path_child(target_directory, basename(source))
    if LrFileUtils.exists(target) then
        target = path_child(target_directory, os.time() .. "-" .. basename(source))
    end
    local ok = pcall(function()
        LrFileUtils.move(source, target)
    end)
    if ok then return target end

    local contents = read_text(source)
    if contents and write_text(target, contents) then
        LrFileUtils.delete(source)
        return target
    end
    return source
end

local function decode_request(path)
    local text = read_text(path)
    if not text or text == "" then return nil, "empty request" end
    local decoded = {
        id = json_string_field(text, "id") or basename(path),
        eventName = json_string_field(text, "eventName") or "",
        importFolder = json_string_field(text, "importFolder") or json_string_field(text, "folder"),
        folder = json_string_field(text, "folder"),
        createdAt = json_string_field(text, "createdAt") or "",
        recursive = json_boolean_field(text, "recursive") or false,
    }
    if not decoded.importFolder or decoded.importFolder == "" then
        return nil, "missing importFolder"
    end
    return decoded, nil
end

local function file_extension(path)
    local ext = string.match(path, "%.([^%.%/]+)$")
    return ext and string.lower(ext) or ""
end

local function is_supported_raw(path)
    return SUPPORTED_RAW_EXTENSIONS[file_extension(path)] == true
end

local function list_raw_files_non_recursive(folder)
    local files = {}
    for file_path in LrFileUtils.files(folder) do
        if is_supported_raw(file_path) then
            table.insert(files, file_path)
        end
    end
    table.sort(files)
    return files
end

local function find_photo_by_path(catalog, file_path)
    -- Read-only lookup. Called directly inside the LrTask (no pcall) because
    -- pcall cannot span a yield in Lua 5.1.
    return catalog:findPhotoByPath(file_path)
end

local function import_files_to_catalog(files)
    local catalog = LrApplication.activeCatalog()
    local imported = 0
    local failed = 0
    local first_error = ""

    if #files == 0 then
        return 0, 0, 0, "", true
    end

    -- All addPhoto calls in a SINGLE write transaction — fast even for large events.
    -- No per-file findPhotoByPath dedup: that read yields once per file (slow for
    -- thousands) and is unnecessary because addPhoto is idempotent — if a file is
    -- already in the catalog it returns the existing photo without creating a
    -- duplicate. addPhoto is synchronous inside withWriteAccessDo (it does not yield),
    -- so it is safe in this no-yield block.
    catalog:withWriteAccessDo("Aurora Sync", function()
        for _, file_path in ipairs(files) do
            local photo = catalog:addPhoto(file_path)
            if photo then
                imported = imported + 1
            else
                failed = failed + 1
                if first_error == "" then
                    first_error = "addPhoto returned nil for " .. file_path
                end
            end
        end
    end, { timeout = 120 })

    return imported, 0, failed, first_error, true
end

local function append_result(request, status, details)
    return table.concat({
        "{",
        '  "id": "' .. json_escape(request.id) .. '",',
        '  "eventName": "' .. json_escape(request.eventName) .. '",',
        '  "importFolder": "' .. json_escape(request.importFolder or request.folder) .. '",',
        '  "recursive": false,',
        '  "createdAt": "' .. json_escape(request.createdAt) .. '",',
        '  "status": "' .. json_escape(status) .. '",',
        '  "completedAt": "' .. os.date("!%Y-%m-%dT%H:%M:%SZ") .. '",',
        '  "result": {',
        '    "importFolder": "' .. json_escape(details.importFolder or "") .. '",',
        '    "found": ' .. tostring(details.found or 0) .. ',',
        '    "imported": ' .. tostring(details.imported or 0) .. ',',
        '    "skipped": ' .. tostring(details.skipped or 0) .. ',',
        '    "failed": ' .. tostring(details.failed or 0) .. ',',
        '    "error": "' .. json_escape(details.error or "") .. '"',
        '  }',
        "}",
    }, "\n")
end

local function fail_request(request_path, message)
    local p = ensure_directories()
    local request = decode_request(request_path) or {}
    local failed_path = move_request(request_path, p.failed)
    write_text(failed_path, append_result(request, "failed", { error = message }))
    log_line("failed " .. basename(request_path) .. ": " .. message)
end

local function process_request(request_path)
    local p = ensure_directories()
    local processing_path = move_request(request_path, p.processing)
    local request, decode_error = decode_request(processing_path)
    if not request then
        fail_request(processing_path, decode_error or "invalid request")
        return
    end

    local folder = request.importFolder or request.folder
    if not folder or folder == "" then
        fail_request(processing_path, "missing importFolder")
        return
    end

    if LrFileUtils.exists(folder) ~= "directory" then
        fail_request(processing_path, "folder not found: " .. folder)
        return
    end

    local raw_files = list_raw_files_non_recursive(folder)
    local imported, skipped, failed, first_error, executed = import_files_to_catalog(raw_files)

    -- If there were files to import but the catalog write block never ran (executed=false),
    -- the catalog was busy. Do NOT mark this done/failed — return it to pending so the next
    -- poll retries, instead of silently losing the request.
    if (not executed) and #raw_files > 0 then
        move_request(processing_path, p.pending)
        log_line("retry " .. basename(processing_path) .. ": catalog busy, returned to pending (found=" .. #raw_files .. ")")
        return
    end

    local status = imported > 0 or failed == 0
    local target_dir = status and p.done or p.failed
    local final_status = status and "done" or "failed"
    local final_path = move_request(processing_path, target_dir)
    write_text(final_path, append_result(request, final_status, {
        importFolder = folder,
        found = #raw_files,
        imported = imported,
        skipped = skipped,
        failed = failed,
        error = first_error,
        recursive = false,
    }))

    log_line(final_status .. " " .. basename(final_path) .. ": found=" .. #raw_files .. " imported=" .. imported .. " skipped=" .. skipped .. " failed=" .. failed .. " error=" .. tostring(first_error))
end

local function pending_requests()
    local p = ensure_directories()
    local requests = {}
    for file_path in LrFileUtils.files(p.pending) do
        if file_extension(file_path) == "json" then
            table.insert(requests, file_path)
        end
    end
    table.sort(requests)
    return requests
end

function SyncPendingImports.check_once()
    for _, request_path in ipairs(pending_requests()) do
        local protected_call = LrTasks.pcall or pcall
        local ok, error_message = protected_call(function()
            process_request(request_path)
        end)
        if not ok then
            fail_request(request_path, tostring(error_message))
        end
    end
end

function SyncPendingImports.prepare()
    ensure_directories()
    log_line("Aurora Sync prepared at " .. sync_root())
end

function SyncPendingImports.start()
    SyncPendingImports.prepare()
    log_line("Aurora Sync started")
    while true do
        local protected_call = LrTasks.pcall or pcall
        local ok, error_message = protected_call(function()
            SyncPendingImports.check_once()
        end)
        if not ok then
            log_line("background sync error: " .. tostring(error_message))
        end
        LrTasks.sleep(CHECK_INTERVAL_SECONDS)
    end
end

-- Process every pending request once and return a human-readable summary string.
-- Called by the menu command. Must run inside an LrTask (the menu wraps it in one).
function SyncPendingImports.run_now()
    local p = ensure_directories()
    local requests = pending_requests()
    if #requests == 0 then
        return "No pending imports found.\n\nWatched folder:\n" .. p.pending
    end

    local lines = { "Watched folder:", p.pending, "" }
    local total_imported, total_found = 0, 0

    for _, request_path in ipairs(requests) do
        local request, decode_error = decode_request(request_path)
        if not request then
            table.insert(lines, basename(request_path) .. ": invalid (" .. tostring(decode_error) .. ")")
            move_request(request_path, p.failed)
        else
            local folder = request.importFolder or request.folder
            if not folder or LrFileUtils.exists(folder) ~= "directory" then
                table.insert(lines, (request.eventName or "?") .. ": folder not found")
                move_request(request_path, p.failed)
            else
                local raw_files = list_raw_files_non_recursive(folder)
                local imported, skipped, failed, first_error, executed = import_files_to_catalog(raw_files)
                total_imported = total_imported + imported
                total_found = total_found + #raw_files
                table.insert(lines, (request.eventName or "?") .. ": found=" .. #raw_files ..
                    " imported=" .. imported .. " skipped=" .. skipped .. " failed=" .. failed ..
                    (first_error ~= "" and ("\n   err: " .. first_error) or ""))
                if (not executed) and #raw_files > 0 then
                    -- catalog was busy; leave in pending for the next run
                    move_request(request_path, p.pending)
                else
                    move_request(request_path, (imported > 0 or failed == 0) and p.done or p.failed)
                end
                log_line("run_now " .. (request.eventName or "?") .. ": found=" .. #raw_files ..
                    " imported=" .. imported .. " skipped=" .. skipped .. " failed=" .. failed ..
                    " executed=" .. tostring(executed) .. " err=" .. tostring(first_error))
            end
        end
    end

    table.insert(lines, "")
    table.insert(lines, "TOTAL imported: " .. total_imported .. "  (found " .. total_found .. ")")
    return table.concat(lines, "\n")
end

return SyncPendingImports
