return {
    LrSdkVersion = 6.0,
    LrSdkMinimumVersion = 6.0,
    LrToolkitIdentifier = "errormedia.aurorasync",
    LrPluginName = "Aurora Sync",
    -- Menu-only design (the LrInitPlugin watcher does not reliably re-run on relaunch
    -- in Lightroom Classic 15.x). The command is exposed in two places so it can be
    -- both clicked manually and triggered reliably by the Aurora app:
    --   * File menu  > Plug-in Extras  (LrExportMenuItems)  — present in ALL modules;
    --     this is what the Aurora app clicks via AppleScript.
    --   * Library menu > Plug-in Extras (LrLibraryMenuItems) — convenient in Library.
    LrExportMenuItems = {
        {
            title = "Import Aurora Photos Now",
            file = "MenuItem.lua",
        },
    },
    LrLibraryMenuItems = {
        {
            title = "Import Aurora Photos Now",
            file = "MenuItem.lua",
        },
    },
    LrPluginInfoUrl = "https://errormedia.pt/aurora",
    VERSION = {
        major = 1,
        minor = 0,
        revision = 0,
        build = 20,
    },
}
