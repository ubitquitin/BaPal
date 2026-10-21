
-- ============================================
-- BA Pal
-- ============================================

local parent = ui.Interfaces:GetComponent(
    id.Component.TOPLEVEL_V2__GAME_AREA
)

local ba_app = prettyui.Window.new(parent, {
    title = "BA Pal",
    x = 149,
    y = 336,
    width = 550,
    height = 650,
    minWidth = 510,
    minHeight = 350,
    rowBackgroundColours = {
        0x24211EFF,
        0x2E2825FF
    },
    resizable = true
})

-- ============================================
-- Variable access
-- ============================================

local function vp(id)
    local ok, value = pcall(function()
        local config = var.VarPlayer.FromID(id)
        return config and config.value or nil
    end)
    return ok and value or nil
end

local VAR = {
    MODE = 4688,
    WAVE = -22919,
    ROUND_TIME = 4690,
    ROLE = 1494,
    KING_KILL_CURRENCY = -22920,
    QUEEN_KILL_CURRENCY = -4509,
    REWARD_TYPE = -4537,

    CURRENT_ATTACKER = -4519,
    CURRENT_DEFENDER = -4527,
    CURRENT_COLLECTOR = -4525,
    CURRENT_HEALER = -4526,

    HIGHSCORE_ATTACKER = 1495,
    HIGHSCORE_DEFENDER = 1496,
    HIGHSCORE_COLLECTOR = 1497,
    HIGHSCORE_HEALER = 1498
}

local ROLE_NAMES = {
    [0] = "No Role Set",
    [1] = "Attacker",
    [2] = "Defender",
    [3] = "Collector",
    [4] = "Healer"
}

-- ============================================
-- Configuration
-- ============================================

-- Set to "previous" if the round timer resets
-- on the same tick as the wave number changes.
-- Set to "current" if the completed time is
-- still available on the transition tick.
local SPLIT_TIMER_SOURCE = "previous"

-- Assumes 4690 represents game ticks.
-- One RuneScape game tick is approximately 0.6s.
-- Change to 1 if 4690 already represents seconds.
local SECONDS_PER_TIMER_UNIT = 0.6

-- ============================================
-- Shared application state
-- ============================================

local state = {
    tick = 0,
    serverTick = 0, -- Monotonic tick counter, including time between waves
    waveStartTick = nil,
    waveElapsedTicks = nil,

    currentMode = nil,
    currentWave = nil,
    previousTimer = nil,

    -- Only a RegionCreated event starts an active wave.
    inWave = false,
    activeWave = nil,
    activeMode = nil,

    -- Set at wave increment, consumed at the next RegionCreated.
    quickstartStartTick = nil,
    quickstartTargetWave = nil,
    quickstartMode = nil,

    splits = { normal = {}, hard = {} },
    quickstarts = { normal = {}, hard = {} },

    kingActive = false,
    kingStartTick = nil,
    kingSpawnDetected = false,
    kingFoodStartTick = nil
}

-- ============================================
-- Tabs
-- ============================================

local tabs = ba_app:AddTabs({
    { text = "Wave Splits" },
    { text = "Wave Tick" },
    { text = "Penance King" }
}, {
    height = 365,
    activeIndex = 1
})

local splitPage = tabs:GetPage(1)
local tickPage = tabs:GetPage(2)
local kingPage = tabs:GetPage(3)

-- ============================================
-- Wave Splits UI
-- ============================================

local modeLabel = splitPage:AddText({
    text = "Mode: --",
    colour = 0xE8BD83FF
})

local waveLabel = splitPage:AddText({
    text = "Current Wave: --"
})

-- Fixed-width inline columns avoid spacing drift with proportional fonts.
local function splitCell(text, width, colour, first)
    return splitPage:AddText({
        text = text,
        width = width,
        height = 22,
        inline = not first,
        columnGap = 4,
        colour = colour,
        marginTop = 0,
        marginBottom = 0
    })
end

splitCell("WAVE", 115, 0xE8BD83FF, true)
splitCell("TIME", 90, 0xE8BD83FF, false)
splitCell("QUICKSTART", 140, 0xE8BD83FF, false)

local splitRows = {}
for wave = 1, 9 do
    splitCell("Wave " .. wave, 115, nil, true)
    local timeCell = splitCell("--:--", 90, nil, false)
    local quickCell = splitCell("--", 140, nil, false)
    splitRows[wave] = { time = timeCell, quick = quickCell }
end

local totalLabel = splitPage:AddText({
    text = "Total (1-9): --:--",
    colour = 0xE8BD83FF,
    marginTop = 10
})

local function formatTime(raw)
    if raw == nil then
        return "--:--"
    end

    local seconds = math.floor(
        raw * SECONDS_PER_TIMER_UNIT
    )

    return string.format(
        "%02d:%02d",
        math.floor(seconds / 60),
        seconds % 60
    )
end

local function refreshSplits()
    local mode = state.currentMode

    modeLabel.content = "Mode: " .. (
        mode == "hard" and "Hard"
        or mode == "normal" and "Normal"
        or "--"
    )

    waveLabel.content = "Current Wave: " ..
        tostring(state.currentWave or "--")

    local totalTicks = 0
    local complete = mode ~= nil
    for wave = 1, 9 do
        local split = mode and state.splits[mode][wave] or nil
        -- Quickstart belongs to the wave being exited, not the next wave.
        local quickstart = (mode and wave < 9)
            and state.quickstarts[mode][wave] or nil
        splitRows[wave].time.content = formatTime(split)
        splitRows[wave].quick.content = wave == 9 and "--"
            or quickstart ~= nil and (tostring(quickstart) .. " ticks") or "--"
        if split == nil or (wave < 9 and quickstart == nil) then
            complete = false
        else
            totalTicks = totalTicks + split + (quickstart or 0)
        end
    end
    totalLabel.content = "Total (1-9): " .. (complete and formatTime(totalTicks) or "--:--")
end

-- ============================================
-- Wave Tick UI
-- ============================================

tickPage:AddTitle("Current Tick")

local tickLabel = tickPage:AddText({
    text = "--",
    colour = 0xE8BD83FF,
    height = 50
})

tickPage:AddText("Repeats every 10 server ticks (during wave only)")

local tickStatusLabel = tickPage:AddText({
    text = "Status: Waiting for wave"
})

local timerLabel = tickPage:AddText({
    text = "Wave time (ticks): --"
})

local callChangeLabel = tickPage:AddText({
    text = "Call change in: --"
})

-- Exactly 50 game ticks = 30 seconds per call cycle.
local CALL_CHANGE_TICKS = 50
local SECONDS_PER_GAME_TICK = 0.6

local function updateWaveTimers()
    if state.inWave and state.waveStartTick ~= nil then
        local elapsed = math.max(0, state.serverTick - state.waveStartTick)
        state.waveElapsedTicks = elapsed
        timerLabel.content = "Wave time (ticks): " .. tostring(elapsed)

        local remainingTicks = CALL_CHANGE_TICKS - (elapsed % CALL_CHANGE_TICKS)
        local remainingSeconds = remainingTicks * SECONDS_PER_GAME_TICK
        callChangeLabel.content = string.format("Call change in: %.1fs", remainingSeconds)
    else
        timerLabel.content = "Wave time (ticks): " ..
            tostring(state.waveElapsedTicks ~= nil and state.waveElapsedTicks or "--")
        callChangeLabel.content = "Call change in: --"
    end
end

local tickWaveLabel = tickPage:AddText({
    text = "Wave: --"
})

local tickModeLabel = tickPage:AddText({
    text = "Mode: --"
})

-- ============================================
-- Penance King UI and timing
-- ============================================

local KING_NPC_ID = 19670
local KING_SPAWN_TICKS = 600  -- 6 minutes at 600 ms per server tick
local KING_FOOD_TICKS = 36
local KING_POLL_BELOW_TICKS = 9 -- strictly below 5 seconds
local KING_GREEN = 0x44DD66FF
local KING_YELLOW = 0xFFE04AFF
local KING_RED = 0xFF5555FF

kingPage:AddTitle("Time till spawn")
-- Three fixed-size, inline labels share one visual row. Only the active
-- colour label contains text. Native ui.Text.height is read-only, so do not
-- attempt to resize or hide labels by assigning to .height.
local kingSpawnLabels = {
    green = kingPage:AddText({ text = "06:00", colour = KING_GREEN,
        width = 105, height = 42, marginBottom = 0 }),
    yellow = kingPage:AddText({ text = "", colour = KING_YELLOW,
        width = 105, height = 42, inline = true, marginBottom = 0 }),
    red = kingPage:AddText({ text = "", colour = KING_RED,
        width = 105, height = 42, inline = true, marginBottom = 0 })
}
local function showKingTimer(text, colour)
    for name, label in pairs(kingSpawnLabels) do
        label.content = (name == colour) and text or ""
    end
end

local kingStatusLabel = kingPage:AddText({
    text = "Waiting for hard-mode wave 10"
})

kingPage:AddTitle("5 bucket 1st food drop:")
local kingFoodLabel = kingPage:AddText({
    text = "--",
    height = 45
})

kingPage:AddTitle("Stored BA kills")
local kingKillsLabel = kingPage:AddText({ text = "King kills: -- / 50" })
local queenKillsLabel = kingPage:AddText({ text = "Queen kills: -- / 1" })

local function updateStoredKills()
    local kingKills = vp(VAR.KING_KILL_CURRENCY)
    local queenKills = vp(VAR.QUEEN_KILL_CURRENCY)
    kingKillsLabel.content = "King kills: " .. tostring(kingKills ~= nil and kingKills or "--") .. " / 20"
    queenKillsLabel.content = "Queen kills: " .. tostring(queenKills ~= nil and queenKills or "--") .. " / 1"
end

local function resetKing()
    state.kingActive = false
    state.kingStartTick = nil
    state.kingSpawnDetected = false
    state.kingFoodStartTick = nil
    showKingTimer("06:00", "green")
    kingFoodLabel.content = "--"
    kingStatusLabel.content = "Waiting for hard-mode wave 10"
end

local function startKing()
    if state.kingActive then return end
    state.kingActive = true
    state.kingStartTick = state.serverTick
    state.kingSpawnDetected = false
    state.kingFoodStartTick = nil
    showKingTimer("06:00", "green")
    kingFoodLabel.content = "--"
    kingStatusLabel.content = "Waiting for Penance King"
    print("BA Penance King: hard-mode wave 10 region entered")
end

-- PlayerList-style ByDistance API; only queried near expected spawn.
local function kingNpcPresent()
    local ok, npcs = pcall(function()
        local self = PlayerList.Self()
        if not self or not self.isValid then return nil end
        return NPCList.ByDistance(self.coordGrid, 64)
    end)
    if not ok or not npcs then return false end

    for _, npc in ipairs(npcs) do
        if npc and npc.isValid ~= false then
            -- Different API versions may expose the NPC type ID differently.
            local found, npcId = pcall(function()
                return npc.id or npc.npcId or npc.typeId or npc.typeID
            end)
            if found and tonumber(npcId) == KING_NPC_ID then
                return true
            end
        end
    end
    return false
end

local function updateKing()
    if not state.kingActive then return end

    local elapsed = math.max(0, state.serverTick - state.kingStartTick)
    local remaining = math.max(0, KING_SPAWN_TICKS - elapsed)
    local seconds = math.ceil(remaining * 0.6)
    local colour = remaining <= 50 and "red"
        or remaining <= 100 and "yellow" or "green"
    showKingTimer(string.format("%02d:%02d",
        math.floor(seconds / 60), seconds % 60), colour)

    -- Poll only within five seconds of expected spawn.
    -- Start the food timer immediately when the King is detected,
    -- regardless of whether the spawn countdown has reached zero.
    if not state.kingSpawnDetected and remaining < KING_POLL_BELOW_TICKS
        and kingNpcPresent() then
        state.kingSpawnDetected = true
        state.kingFoodStartTick = state.serverTick
        kingStatusLabel.content = "Penance King detected"
    end

    if state.kingFoodStartTick ~= nil then
        local foodElapsed = state.serverTick - state.kingFoodStartTick
        kingFoodLabel.content = tostring(math.max(0, KING_FOOD_TICKS - foodElapsed))
    else
        kingFoodLabel.content = "--"
    end
end

-- ============================================
-- Player Information UI
-- ============================================

ba_app:AddText({
    text = "PLAYER INFORMATION",
    colour = 0xE8BD83FF,
    marginTop = 8
})

local roleLabel = ba_app:AddText({
    text = "Role: --"
})

local rewardTypeLabel = ba_app:AddText({
    text = "Reward Type: --"
})

ba_app:AddText({
    text = "Current Points",
    colour = 0xE8BD83FF
})

local currentPointsLabel = ba_app:AddText({
    text = "A: --  D: --  C: --  H: --",
    height = 24
})

ba_app:AddText({
    text = "Highscore Points",
    colour = 0xE8BD83FF
})

local highscorePointsLabel = ba_app:AddText({
    text = "A: --  D: --  C: --  H: --",
    height = 24
})

-- ============================================
-- Player Information Updates
-- ============================================

local function pointString(value)
    if value == nil then
        return "--"
    end

    local formatted = tostring(value)

    -- Insert commas every 3 digits
    while true do
        local result, count = formatted:gsub(
            "^(-?%d+)(%d%d%d)",
            "%1,%2"
        )

        formatted = result

        if count == 0 then
            break
        end
    end

    return formatted
end

local function formatPoints(a, d, c, h)
    return string.format(
        "A: %s  D: %s  C: %s  H: %s",
        pointString(a),
        pointString(d),
        pointString(c),
        pointString(h)
    )
end

local function updatePlayerInfo()
    local role = vp(VAR.ROLE)
    local rewardType = vp(VAR.REWARD_TYPE)
    
    rewardTypeLabel.content = "Reward Type: " .. (
        rewardType == 0 and "Points"
        or rewardType == 1 and "BXP"
        or "Unknown"
    )

    roleLabel.content =
        "Role: " .. (
            ROLE_NAMES[role]
            or tostring(role or "--")
        )

    currentPointsLabel.content = formatPoints(
        vp(VAR.CURRENT_ATTACKER),
        vp(VAR.CURRENT_DEFENDER),
        vp(VAR.CURRENT_COLLECTOR),
        vp(VAR.CURRENT_HEALER)
    )

    highscorePointsLabel.content = formatPoints(
        vp(VAR.HIGHSCORE_ATTACKER),
        vp(VAR.HIGHSCORE_DEFENDER),
        vp(VAR.HIGHSCORE_COLLECTOR),
        vp(VAR.HIGHSCORE_HEALER)
    )


end

-- ============================================
-- Game State / Wave Tracking
-- ============================================

local function resetRun()
    resetKing()
    state.splits = { normal = {}, hard = {} }
    state.quickstarts = { normal = {}, hard = {} }
    state.inWave = false
    state.activeWave = nil
    state.activeMode = nil
    state.tick = 0
    state.waveStartTick = nil
    state.waveElapsedTicks = nil
    updateWaveTimers()
    state.quickstartStartTick = nil
    state.quickstartTargetWave = nil
    state.quickstartMode = nil
    tickLabel.content = "--"
    tickStatusLabel.content = "Status: Waiting for wave"
end

local updateGameState -- Forward declaration for RegionCreated callback

-- Called by RegionCreated; this is the ONLY way to start a wave.
local function startWaveFromRegion()
    local modeValue = vp(VAR.MODE)
    local waveValue = vp(VAR.WAVE)
    local mode = modeValue == 0 and "normal"
        or modeValue == 1 and "hard" or nil

    if mode == "hard" and waveValue == 10 then
        updateGameState()
        startKing()
        return
    end

    if not mode or type(waveValue) ~= "number"
        or waveValue < 1 or waveValue > 9 then
        print("BA RegionCreated: ignored (no valid BA mode/wave)")
        return
    end

    -- Reconcile any wave transition not yet observed by ServerLogic.
    updateGameState()

    state.currentMode = mode
    state.currentWave = waveValue

    -- Avoid restarting the tick counter on repeated region events.
    if state.inWave then
        print("BA RegionCreated: already in wave; ignored")
        return
    end

    if state.quickstartStartTick ~= nil
        and state.quickstartTargetWave == waveValue
        and state.quickstartMode == mode then
        state.quickstarts[mode][waveValue - 1] =
            state.serverTick - state.quickstartStartTick
        print(string.format("BA quickstart: wave=%d ticks=%d",
            waveValue - 1, state.quickstarts[mode][waveValue - 1]))
    end

    state.quickstartStartTick = nil
    state.quickstartTargetWave = nil
    state.quickstartMode = nil
    state.inWave = true
    state.activeWave = waveValue
    state.activeMode = mode
    state.tick = 0
    state.waveStartTick = state.serverTick
    state.waveElapsedTicks = 0
    updateWaveTimers()
    tickLabel.content = "0"
    tickStatusLabel.content = "Status: In wave"

    print(string.format("BA wave started (RegionCreated): %s wave %d",
        mode, waveValue))
    refreshSplits()
end

updateGameState = function()
    local modeValue = vp(VAR.MODE)
    local waveValue = vp(VAR.WAVE)
    local timerValue = vp(VAR.ROUND_TIME)

    local newMode = modeValue == 0 and "normal"
        or modeValue == 1 and "hard" or nil

    if not newMode or type(waveValue) ~= "number" then
        return
    end

    -- Leaving hard wave 10 (including a run restart) cancels its timers.
    if state.kingActive and (newMode ~= "hard" or waveValue ~= 10) then
        resetKing()
    end

    if state.currentWave == nil then
        state.currentMode = newMode
        state.currentWave = waveValue
        state.previousTimer = timerValue
        refreshSplits()
    else
        local oldWave = state.currentWave
        local oldMode = state.currentMode

        if waveValue < oldWave or newMode ~= oldMode then
            print(string.format("BA run reset: %s wave %s -> %s wave %s",
                tostring(oldMode), tostring(oldWave), newMode,
                tostring(waveValue)))
            resetRun()
        elseif waveValue > oldWave then
            print(string.format("BA wave transition: %d -> %d",
                oldWave, waveValue))

            -- Only record a split if RegionCreated actually started
            -- the completed wave, and this is a sequential increment.
            if state.inWave and state.activeWave == oldWave
                and state.activeMode == oldMode
                and waveValue == oldWave + 1 then
                local completedTime = SPLIT_TIMER_SOURCE == "previous"
                    and state.previousTimer or timerValue
                if completedTime ~= nil then
                    state.splits[oldMode][oldWave] = completedTime
                    print(string.format("BA split: %s wave=%d time=%s",
                        oldMode, oldWave, tostring(completedTime)))
                end

                -- The next wave's quickstart begins NOW, at increment.
                state.quickstartStartTick = state.serverTick
                state.quickstartTargetWave = waveValue
                state.quickstartMode = newMode
            else
                -- Skip / missed start: no trustworthy quickstart origin.
                state.quickstartStartTick = nil
                state.quickstartTargetWave = nil
                state.quickstartMode = nil
            end

            -- Freeze the completed wave's elapsed time until the next entry.
            if state.waveStartTick ~= nil then
                state.waveElapsedTicks = math.max(0, state.serverTick - state.waveStartTick)
            end
            state.waveStartTick = nil
            state.inWave = false
            updateWaveTimers()
            state.activeWave = nil
            state.activeMode = nil
            state.tick = 0
            tickLabel.content = "--"
            tickStatusLabel.content = "Status: Between waves"
        end

        state.currentMode = newMode
        state.currentWave = waveValue
        refreshSplits()
    end

    state.previousTimer = timerValue
    tickWaveLabel.content = "Wave: " .. tostring(waveValue)
    tickModeLabel.content = "Mode: " ..
        (newMode == "hard" and "Hard" or "Normal")
end

-- ============================================
-- Server Tick
-- ============================================

Event.ServerLogic.Subscribe(
    "serverLogicEvent",
    function()
        state.serverTick = state.serverTick + 1
        -- Detect wave completion before advancing the display counter.
        updateGameState()
        updateKing()
        updateWaveTimers()
        updateStoredKills()

        --DEBUG
        print('BARBASSAULT_COLLECTOR_USED ' .. vp(4683))
        print('BARBASSAULT_KING_PLAYER ' .. vp(4684))


        if state.inWave then
            tickLabel.content = tostring(state.tick)
            state.tick = (state.tick + 1) % 10
        else
            tickLabel.content = "--"
        end

        updatePlayerInfo()
    end
)

-- A region transition is our authoritative wave-start signal.
Event.RegionCreated.Subscribe(
    "baRegionCreated",
    function(event)
        startWaveFromRegion()
    end
)

-- ============================================
-- Initialization
-- ============================================

refreshSplits()
resetKing()
updateGameState()
updateWaveTimers()
updateStoredKills()
updatePlayerInfo()

ba_app:RefreshRowBackgrounds()

-- ============================================
-- Shutdown
-- ============================================

function PluginShutdown()
    Event.ServerLogic.Unsubscribe(
        "serverLogicEvent"
    )

    Event.RegionCreated.Unsubscribe(
        "baRegionCreated"
    )

    ba_app:Destroy()
end
