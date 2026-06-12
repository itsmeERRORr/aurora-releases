local LrTasks = import "LrTasks"
local LrFunctionContext = import "LrFunctionContext"
local LrDialogs = import "LrDialogs"

-- Runs when the user picks Library > Plug-in Extras > "Import Aurora Photos Now".
--
-- Pattern notes (both matter on Lightroom Classic 15.x):
--   * LrTasks.startAsyncTask  -> gives catalog:withWriteAccessDo a real LrTask context.
--   * LrFunctionContext.callWithContext + addFailureHandler -> catches errors WITHOUT a
--     plain pcall, because withWriteAccessDo yields and Lua 5.1 cannot yield across pcall.
LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext("AuroraSyncRunNow", function(context)
        context:addFailureHandler(function(_, message)
            LrDialogs.message("Aurora Sync — error", tostring(message), "critical")
        end)

        local mod = dofile(_PLUGIN.path .. "/SyncPendingImports.lua")
        local summary = mod.run_now()
        LrDialogs.message("Aurora Sync — result", summary, "info")
    end)
end)
