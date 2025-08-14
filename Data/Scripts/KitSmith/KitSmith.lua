KitSmith = KitSmith or {}
KitSmith._paused = false
KitSmith._sleeping = false
KitSmith._lastConsolidation = 0 -- cooldown tracker

-- 🛠 Default config (fallbacks)
KitSmith.config = {
    debugLogs = true,
    useSleepCleanup = true,  -- true = triggers only on sleep/wake, false = uses live polling
    pollingInterval = 20000, -- only used in live mode
    dryRun = false
}

-- Logging utilities
function KitSmith.Log(msg)
    if KitSmith.config and KitSmith.config.debugLogs then
        System.LogAlways("[KitSmith] " .. tostring(msg))
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
    KitSmith._pollingActive = false -- Reset to ensure polling is allowed
    KitSmith.Initialize(true)

    if not KitSmith.config.useSleepCleanup then
        KitSmith.Log("🔁 Restarting polling from OnGameplayStarted (savegame load)")
        KitSmith.StartPolling()
    end
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
        else
            Log("Woke up → polling will resume shortly")
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
    KitSmith.Log("Polling tick: paused=" .. tostring(KitSmith._paused))
    if not KitSmith._paused then
        KitSmith.ConsolidateKits()
        Info("KitSmith consolidation cycle completed.")
    else
        KitSmith.Log("Polling paused (sleeping)")
    end
    Script.SetTimerForFunction(KitSmith.config.pollingInterval, "KitSmith.PollingTick")
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
    Log("🔍 Scanning inventory for repair kits...")

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

    local kitsByType = {}

    for _, userdata in pairs(invTable) do
        local item = ItemManager.GetItem(userdata)
        if item then
            local class    = tostring(item.class)
            local raw      = ItemManager.GetItemName(item.class) or ""
            local name     = tostring(raw)
            local lname    = name:lower()
            local health   = item.health or 0
            local amount   = item.amount or 1

            -- robust match: handles "repair kit", "repair-kit", "repairkit"
            local isRepair = lname:find("repair%p*%s*kit") or lname:find("repairkit")

            if isRepair then
                local rec = kitsByType[class]
                if not rec then
                    rec = { class = class, name = name, totalHealth = 0, totalCount = 0 }
                    kitsByType[class] = rec
                end
                -- stack-aware accumulation
                rec.totalHealth = rec.totalHealth + (health * amount)
                rec.totalCount  = rec.totalCount + amount
            end
        end
    end


    for kitName, data in pairs(kitsByType) do
        local total = data.totalHealth
        local count = data.totalCount
        if count > 1 then
            local fullKits = math.floor(total)
            local remainder = total - fullKits
            local newCount = fullKits + (remainder > 0 and 1 or 0)

            if newCount < count then
                if KitSmith.config.dryRun then
                    Info(string.format(
                        "Dry-run: %s (count=%d, totalHealth=%.2f) → would create %d full kits and %s remainder kit",
                        kitName, count, total, fullKits,
                        (remainder > 0 and string.format("1 (%.2f)", remainder) or "none")
                    ))
                else
                    Log(string.format("Removing %d original %s kits", count, kitName))
                    player.inventory:DeleteItemOfClass(data.class, count)

                    for i = 1, fullKits do
                        Log("Creating 1 full kit: " .. kitName)
                        player.inventory:CreateItem(data.class, 1.0, 1)
                    end

                    if remainder > 0 then
                        Log("Creating 1 remainder kit: " .. kitName .. " with health=" .. remainder)
                        player.inventory:CreateItem(data.class, remainder, 1)
                    end
                end
            else
                Info(string.format(
                    "No consolidation needed for %s (count=%d, already optimal with totalHealth=%.2f)",
                    kitName, count, total
                ))
            end
        else
            Info(string.format("Keeping %s as is (only %d kit, totalHealth=%.2f)",
                kitName, count, total))
        end
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
