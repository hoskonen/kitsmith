-- Ensure global table exists
KitSmith = KitSmith or {}

-- Bootstrap: load the main logic
Script.ReloadScript("Scripts/KitSmith/KitSmith.lua")

-- Register lifecycle event
UIAction.RegisterEventSystemListener(KitSmith, "System", "OnGameplayStarted", "OnGameplayStarted")
