-- #####################################
-- KitSmith - Configuration
-- #####################################

KitSmith_Config = {
    -- Show detailed logs in the console (true/false)
    debugLogs = false,

    -- Mode selection:
    -- true  = consolidate repair kits when you wake up from sleep (immersive, safest option)
    -- false = consolidate kits every X seconds while playing (live mode, QoL)
    useSleepCleanup = true,

    -- Interval for live mode (milliseconds). Ignored if useSleepCleanup = true.
    pollingInterval = 20000, -- 20s is a good default

    -- If true, no items are changed — only logs are printed (testing/debugging).
    dryRun = false
}
