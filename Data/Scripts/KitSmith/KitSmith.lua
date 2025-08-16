KitSmith = KitSmith or {}
KitSmith._paused = false
KitSmith._sleeping = false
KitSmith._lastConsolidation = 0 -- cooldown tracker

-- 🛠 Default config (fallbacks)
KitSmith.config = {
    debugLogs                = true,
    useSleepCleanup          = true,  -- true = triggers only on sleep/wake, false = uses live polling
    pollingInterval          = 20000, -- only used in live mode
    dryRun                   = false,
    -- Bandages:
    enableBandages           = false,
    bandagesPreview          = true,
    dropTinyBandageRemainder = false, -- set true to enable dropping
    bandageRemainderMin      = 0.05,  -- drop if remainder < 5% of one bandage
    bandageRemainderEpsilon  = 1e-4,  -- treat <1e-4 as zero to kill float noise
    bandageClassWhitelist    = {},    -- will be overridden by KitSmith_Config if provided
    -- Safety: chunk size for CreateItem batching
    maxCreateStack           = 99,
}

-- Max units per CreateItem call (safety for unknown stack caps)
KitSmith.config.maxCreateStack = KitSmith.config.maxCreateStack or 99

local function CreateInChunks(inv, class, health, amount, maxPerStack)
    maxPerStack = maxPerStack or KitSmith.config.maxCreateStack or 99
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    while amount > 0 do
        local n = math.min(amount, maxPerStack)
        inv:CreateItem(class, health, n)
        amount = amount - n
    end
end

-- Logging utilities
function KitSmith.Log(msg)
    if KitSmith.config and KitSmith.config.debugLogs then
        System.LogAlways("[KitSmith] " .. tostring(msg))
    end
end

-- --- Bandage detection helpers --------------------------------------------
local function IsWhitelistedBandage(class)
    local wl = KitSmith.config.bandageClassWhitelist
    return wl and class and wl[tostring(class)] == true
end

local function LooksLikeBandage(name)
    local lname = (name or ""):lower()
    return lname:find("bandage", 1, true) ~= nil
end

local function IsBandage(class, name)
    -- Prefer exact class whitelist; fall back to name match
    if IsWhitelistedBandage(class) then return true end
    return LooksLikeBandage(name)
end

function KitSmith.DebugBandageStacks()
    local player = KitSmith.GetPlayer()
    if not player or not player.inventory then
        Info("DebugBandageStacks: no player/inventory")
        return
    end
    local inv = player.inventory:GetInventoryTable() or {}
    Info("---- Bandage stacks ----")
    local totalUnits, totalUses = 0, 0
    for _, ud in pairs(inv) do
        local item = ItemManager.GetItem(ud)
        if item then
            local class = tostring(item.class)
            local name  = ItemManager.GetItemName(item.class) or ""
            if IsBandage(class, name) then
                local h = item.health or 0
                if h > 1.001 then h = h / 100 end
                h = math.max(0, math.min(1, h))
                local amt = item.amount or 1
                Info(string.format("• %s (class=%s) health=%.2f amount=%d", name, class, h, amt))
                totalUnits = totalUnits + amt
                totalUses  = totalUses + (h * amt)
            end
        end
    end
    Info(string.format("Totals → units=%d uses=%.2f", totalUnits, totalUses))
end

-- 🔻 Stop polling (soft-cancel by flag; next tick won't reschedule)
function KitSmith.StopPolling()
    if KitSmith._pollingActive then
        KitSmith.Log("🛑 Stopping polling loop")
        KitSmith._pollingActive = false
    end
end

function KitSmith.Info(msg)
    System.LogAlways("[KitSmith] " .. tostring(msg))
end

-- Player getter
function KitSmith.GetPlayer()
    return System.GetEntityByName("Henry") or System.GetEntityByName("dude")
end

-- Dump config
function KitSmith.DumpConfig()
    KitSmith.Info("🧩 Active KitSmith config:")
    for k, v in pairs(KitSmith.config) do
        KitSmith.Info(string.format("  - %s = %s", k, tostring(v)))
    end
end

local Log     = KitSmith.Log
local Info    = KitSmith.Info

-- Load user config override (safe)
local ok, err = pcall(function()
    Script.ReloadScript("Scripts/KitSmith/KitSmithConfig.lua")
end)

if not ok then
    Info("⚠ Failed to load KitSmithConfig.lua: " .. tostring(err))
elseif KitSmith_Config then
    for k, v in pairs(KitSmith_Config) do
        KitSmith.config[k] = v
    end
    Info("Loaded config from KitSmithConfig.lua")
else
    Info("⚠ KitSmithConfig.lua loaded but no KitSmith_Config table found")
end

-- Event hooks
function KitSmith.OnGameplayStarted(actionName, eventName, argTable)
    KitSmith.Info("🎮 OnGameplayStarted fired")
    -- soft-cancel any prior loop from an earlier session/config
    KitSmith.StopPolling()
    KitSmith.Initialize(true)
    -- No need to StartPolling here — Initialize() decides based on config
end

function KitSmith:onSkipTimeEvent(elementName, instanceId, eventName, argTable)
    if eventName == "OnSetFaderState" and argTable and argTable[1] == "sleep" then
        if not KitSmith._sleeping then
            KitSmith._sleeping = true
            KitSmith._paused = true
            Log("Sleep session starting → polling paused")
        end
    elseif eventName == "OnHide" and KitSmith._sleeping then
        KitSmith._sleeping = false
        KitSmith._paused = false
        if KitSmith.config.useSleepCleanup then
            Log("Woke up → consolidating kits now")
            KitSmith.ConsolidateKits()
            -- ensure live polling remains OFF in sleep mode
            KitSmith.StopPolling()
        else
            Log("Woke up → polling continues")
        end
    end
end

-- Init
function KitSmith.Initialize(fullInit)
    if fullInit and KitSmith._initialized then
        KitSmith.Log("Already initialized, skipping")
        return
    end
    if fullInit then KitSmith._initialized = true end

    -- Always hook into sleep/wake system (to pause/resume polling)
    if UIAction and UIAction.RegisterElementListener then
        UIAction.RegisterElementListener(KitSmith, "SkipTime", -1, "", "onSkipTimeEvent")
        KitSmith.Log("Registered SkipTime listener for sleep/wake state")
    else
        KitSmith.Log("UIAction not available for SkipTime registration")
    end

    if KitSmith.config.useSleepCleanup then
        -- ensure any previous live loop is stopped
        KitSmith.StopPolling()
        KitSmith.Log("🛏️ Sleep cleanup mode enabled — polling disabled")
    else
        KitSmith.Log("🟢 Live polling mode enabled — starting polling loop")
        KitSmith.StartPolling()
    end

    KitSmith.Log("✅ KitSmith initialized (sleepMode=" .. tostring(KitSmith.config.useSleepCleanup) .. ")")
    KitSmith.DumpConfig() -- ✅ Always dump config after init
end

-- 🔄 Starts the polling function
function KitSmith.StartPolling()
    KitSmith.Log("🔁 Attempting to start polling...")
    if KitSmith._pollingActive then
        KitSmith.Log("Polling already active, skipping")
        return
    end
    local ok = pcall(function()
        Script.SetTimerForFunction(KitSmith.config.pollingInterval, "KitSmith.PollingTick")
        KitSmith._pollingActive = true
        KitSmith.Log("✅ Polling loop started (live mode)")
    end)
    if not ok then
        KitSmith.Log("⚠ Failed to start polling")
    end
    KitSmith.Info(string.format("Polling active every %.1f seconds", KitSmith.config.pollingInterval))
end

-- 🔁 Single polling tick (called repeatedly)
function KitSmith.PollingTick()
    if KitSmith.config.useSleepCleanup or not KitSmith._pollingActive then
        KitSmith.Log("⏸️ Polling tick ignored (sleepMode=" .. tostring(KitSmith.config.useSleepCleanup)
            .. ", active=" .. tostring(KitSmith._pollingActive) .. ")")
        return
    end
    KitSmith.Log("Polling tick: paused=" .. tostring(KitSmith._paused))
    if not KitSmith._paused then
        KitSmith.ConsolidateKits()
    else
        KitSmith.Log("Polling paused (sleeping)")
    end
    if KitSmith._pollingActive then
        Script.SetTimerForFunction(KitSmith.config.pollingInterval, "KitSmith.PollingTick")
    end
end

-- 🔑 Register early to prevent SetTimer failure
_G["KitSmith.PollingTick"] = KitSmith.PollingTick

-- Consolidation logic
function KitSmith.ConsolidateKits()
    local now = System.GetCurrTime()
    KitSmith._lastConsolidation = KitSmith._lastConsolidation or 0

    if now < KitSmith._lastConsolidation then
        Log(string.format("⚠️ Current time (%.1f) is behind last consolidation time (%.1f) — resetting cooldown", now,
            KitSmith._lastConsolidation))
        KitSmith._lastConsolidation = now
    end

    if now - KitSmith._lastConsolidation < 1 then
        Log("Skipping consolidation (cooldown active)")
        return
    end

    KitSmith._lastConsolidation = now
    Log("🔍 Scanning inventory for repair kits" .. (KitSmith.config.enableBandages and " + bandages..." or "..."))

    local player = KitSmith.GetPlayer()
    if not player or not player.inventory then
        Log("No player or inventory found")
        return
    end

    local invTable = player.inventory:GetInventoryTable()
    if not invTable then
        Log("Inventory table empty")
        return
    end

    local kitsByType     = {}
    local bandagesByType = {} -- class → { class, name, totalCount, stackCount }

    for _, userdata in pairs(invTable) do
        local item = ItemManager.GetItem(userdata)
        if item then
            local class    = tostring(item.class)
            local raw      = ItemManager.GetItemName(item.class) or ""
            local name     = tostring(raw)
            local lname    = name:lower()
            local health   = item.health or 0
            local amount   = item.amount or 1

            -- repair kits (existing)
            local isRepair = lname:find("repair%p*%s*kit") or lname:find("repairkit")
            if isRepair then
                local rec         = kitsByType[class] or { class = class, name = name, totalHealth = 0, totalCount = 0 }
                rec.totalHealth   = rec.totalHealth + (health * amount)
                rec.totalCount    = rec.totalCount + amount
                kitsByType[class] = rec
            end

            local rawHealth = item.health or 0
            if rawHealth > 1.001 then rawHealth = rawHealth / 100 end
            local health = math.max(0.0, math.min(1.0, rawHealth))
            local amount = item.amount or 1

            -- bandages aggregation by uses
            if KitSmith.config.enableBandages and IsBandage(class, name) then
                local rec             = bandagesByType[class] or
                    { class = class, name = name, totalUses = 0, totalCount = 0 }
                rec.totalUses         = rec.totalUses + (health * amount)
                rec.totalCount        = rec.totalCount + amount
                bandagesByType[class] = rec
            end
        end
    end

    local totalTypes, totalRemovedStacks, totalCreatedFull, totalCreatedRemainders, totalUnchanged = 0, 0, 0, 0, 0

    for kitName, data in pairs(kitsByType) do
        totalTypes = totalTypes + 1

        local total = data.totalHealth
        local count = data.totalCount
        if count > 1 then
            local fullKits  = math.floor(total)
            local remainder = total - fullKits
            local newCount  = fullKits + (remainder > 0 and 1 or 0)

            if newCount < count then
                if KitSmith.config.dryRun then
                    Log(string.format(
                        "Dry-run: %s (count=%d, totalHealth=%.2f) → would create %d full kits and %s remainder kit",
                        kitName, count, total, fullKits,
                        (remainder > 0 and string.format("1 (%.2f)", remainder) or "none")
                    ))
                else
                    Log(string.format("Removing %d original %s kits", count, kitName))
                    player.inventory:DeleteItemOfClass(data.class, count)
                    totalRemovedStacks = totalRemovedStacks + count

                    if fullKits > 0 then
                        Log("Creating full kits (chunked): " .. kitName .. " x" .. tostring(fullKits))
                        CreateInChunks(player.inventory, data.class, 1.0, fullKits)
                        totalCreatedFull = totalCreatedFull + fullKits
                    end

                    if remainder > 0 then
                        Log("Creating 1 remainder kit: " .. kitName .. " with health=" .. remainder)
                        player.inventory:CreateItem(data.class, remainder, 1)
                        totalCreatedRemainders = totalCreatedRemainders + 1
                    end
                end
            else
                -- Was already optimal
                Log(string.format(
                    "No consolidation needed for %s (count=%d, already optimal with totalHealth=%.2f)",
                    kitName, count, total
                ))
                totalUnchanged = totalUnchanged + 1
            end
        else
            Log(string.format("Keeping %s as is (only %d kit, totalHealth=%.2f)", kitName, count, total))
            totalUnchanged = totalUnchanged + 1
        end
    end

    -- === Bandages (preview or real merge by uses w/ tiny remainder drop) ========
    local bandTypes, bandRemovedUnits, bandCreatedFull, bandCreatedRemainders, bandTotalUses, bandDroppedUses = 0, 0, 0,
        0, 0, 0

    if KitSmith.config.enableBandages then
        local eps  = KitSmith.config.bandageRemainderEpsilon or 1e-4
        local minR = KitSmith.config.bandageRemainderMin or 0.05
        local drop = KitSmith.config.dropTinyBandageRemainder == true

        for _, data in pairs(bandagesByType) do
            bandTypes     = bandTypes + 1
            bandTotalUses = bandTotalUses + data.totalUses

            -- full + remainder with epsilon to kill float noise around integers
            local total   = data.totalUses
            local full    = math.floor(total + eps)
            local rem     = total - full
            if rem < eps then rem = 0 end

            -- Optionally drop tiny remainder
            local willDrop = drop and rem > 0 and rem < minR
            local remOut   = willDrop and 0 or rem
            if willDrop then bandDroppedUses = bandDroppedUses + rem end

            if data.totalCount > 1 then
                if KitSmith.config.bandagesPreview or KitSmith.config.dryRun then
                    Info(string.format(
                        "Bandages PREVIEW: '%s' (class=%s) units=%d uses=%.4f → full=%d, remainder=%.4f%s",
                        data.name or "?", data.class, data.totalCount, total, full, rem,
                        willDrop and string.format(" (would DROP < %.2f)", minR) or ""))
                else
                    Log(string.format(
                        "Merging bandages '%s' (class=%s) units=%d uses=%.4f → full=%d%s",
                        data.name or "?", data.class, data.totalCount, total, full,
                        (remOut > 0) and string.format(" + rem=%.4f", remOut) or
                        (willDrop and string.format(" (dropped rem=%.4f)", rem) or "")))

                    -- delete ALL existing units of that class
                    player.inventory:DeleteItemOfClass(data.class, data.totalCount)
                    bandRemovedUnits = bandRemovedUnits + data.totalCount

                    -- create full units
                    if full > 0 then
                        Log("Creating full bandages (chunked): " .. tostring(full))
                        CreateInChunks(player.inventory, data.class, 1.0, full)
                        bandCreatedFull = bandCreatedFull + full
                    end

                    if remOut > 0 then
                        player.inventory:CreateItem(data.class, remOut, 1)
                        bandCreatedRemainders = bandCreatedRemainders + 1
                    end

                    -- create remainder unit if keeping it
                    if remOut > 0 then
                        player.inventory:CreateItem(data.class, remOut, 1)
                        bandCreatedRemainders = bandCreatedRemainders + 1
                    end
                end
            else
                Log(string.format("Bandage '%s' (class=%s) already single unit → uses=%.4f",
                    data.name or "?", data.class, total))
            end
        end
    end

    if next(kitsByType) or (KitSmith.config.enableBandages and next(bandagesByType)) then
        local summary = string.format(
            "KitSmith: consolidated kits[type=%d removed=%d full=%d rem=%d unchanged=%d]",
            totalTypes, totalRemovedStacks, totalCreatedFull, totalCreatedRemainders, totalUnchanged
        )
        if KitSmith.config.enableBandages then
            summary = summary .. string.format(
                " | bandages[type=%d totalUses=%.4f %s%s]",
                bandTypes, bandTotalUses,
                (KitSmith.config.bandagesPreview or KitSmith.config.dryRun)
                and "PREVIEW"
                or string.format("removedUnits=%d createdFull=%d createdRemainders=%d",
                    bandRemovedUnits, bandCreatedFull, bandCreatedRemainders),
                (bandDroppedUses > 0) and string.format(" dropped=%.4f", bandDroppedUses) or ""
            )
        end
        Info(summary)
    else
        Info("KitSmith: no repair kits/bandages found to consolidate")
    end
end

-- Debug helper
function KitSmith.GiveTestKits()
    local player = KitSmith.GetPlayer()
    if not player or not player.inventory then
        Log("No player or inventory for test kits")
        return
    end

    local kits = {
        { id = "85310d06-2845-46ee-be8f-295503b35035", health = 0.2,  amount = 1 },
        { id = "85310d06-2845-46ee-be8f-295503b35035", health = 0.5,  amount = 1 },
        { id = "c707733a-c0a7-4f02-b684-9392b0b15b83", health = 1.0,  amount = 23 },
        { id = "c707733a-c0a7-4f02-b684-9392b0b15b83", health = 0.53, amount = 1 },
        -- add more with custom amounts if needed
        -- { id = "...", health = 1.0, amount = 34 },
    }

    for _, kit in ipairs(kits) do
        local health = math.max(0.0, math.min(1.0, tonumber(kit.health) or 1.0))
        local amount = math.max(1, math.floor(tonumber(kit.amount) or 1))
        player.inventory:CreateItem(kit.id, health, amount)
        Info(string.format("Spawned test kit: %s (health=%.2f, amount=%d)", kit.id, health, amount))
    end
end

-- Register main event hooks
UIAction.RegisterEventSystemListener(KitSmith, "System", "OnGameplayStarted", "OnGameplayStarted")
