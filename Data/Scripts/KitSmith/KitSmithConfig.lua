-- #####################################
-- KitSmith - Configuration
-- #####################################

KitSmith_Config = {
    -- Show detailed logs in the console (true/false)
    debugLogs                = false,

    -- Mode selection:
    -- true  = consolidate repair kits when you wake up from sleep (immersive, safest option)
    -- false = consolidate kits every X seconds while playing (live mode, QoL)
    useSleepCleanup          = true,

    -- Interval for live mode (milliseconds). Ignored if useSleepCleanup = true.
    pollingInterval          = 20000, -- 20s is a good default

    -- If true, no items are changed — only logs are printed (testing/debugging).
    dryRun                   = false,

    -- NEW: bandage consolidation
    enableBandages           = true,  -- turn bandage handling on/off
    bandagesPreview          = false, -- true = log-only (no deletes/creates) for bandages
    dropTinyBandageRemainder = true,  -- set true to enable dropping
    bandageRemainderMin      = 0.05,  -- drop if remainder < 5% of one bandage
    bandageRemainderEpsilon  = 1e-4,  -- treat <1e-4 as zero to kill float noise
    -- Optional whitelist of bandage classes (fills after first preview run)
    -- Whitelist of bandage classes (from your item.xml)
    bandageClassWhitelist    = {
        ["9fa3000e-3807-48a8-bed8-81427f0bda55"] = true, -- bandage_classic
        ["61f9f0db-1f71-4a5f-9970-7c1bb6e6dfb1"] = true, -- bandage_buffedTest
    },
    -- Safety: chunk size for CreateItem batching
    maxCreateStack           = 99,
}
