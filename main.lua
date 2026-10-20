
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
    width = 440,
    height = 510,
    minWidth = 340,
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
    quickstarts = { normal = {}, hard = {} }
}

-- ============================================
-- Tabs
-- ============================================

local tabs = ba_app:AddTabs({
    { text = "Wave Splits" },
    { text = "Wave Tick" }
}, {
    height = 265,
    activeIndex = 1
})

local splitPage = tabs:GetPage(1)
local tickPage = tabs:GetPage(2)

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

splitPage:AddText({
    text = "WAVE       TIME       QUICKSTART",
    colour = 0xE8BD83FF
})

local splitRows = {}

for wave = 1, 9 do
    splitRows[wave] = splitPage:AddText({
        text = string.format(
            "Wave %d       --:--       --",
            wave
        ),
        height = 20
    })
end

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

    for wave = 1, 9 do
        local split = mode and state.splits[mode][wave] or nil
        local quickstart = mode and state.quickstarts[mode][wave] or nil
        splitRows[wave].content = string.format(
            "Wave %d       %s       %s",
            wave,
            formatTime(split),
            quickstart ~= nil and (tostring(quickstart) .. " ticks") or "--"
        )
    end
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
    text = "Round timer: --"
})

local tickWaveLabel = tickPage:AddText({
    text = "Wave: --"
})

local tickModeLabel = tickPage:AddText({
    text = "Mode: --"
})

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
    state.splits = { normal = {}, hard = {} }
    state.quickstarts = { normal = {}, hard = {} }
    state.inWave = false
    state.activeWave = nil
    state.activeMode = nil
    state.tick = 0
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
        state.quickstarts[mode][waveValue] =
            state.serverTick - state.quickstartStartTick
        print(string.format("BA quickstart: wave=%d ticks=%d",
            waveValue, state.quickstarts[mode][waveValue]))
    end

    state.quickstartStartTick = nil
    state.quickstartTargetWave = nil
    state.quickstartMode = nil
    state.inWave = true
    state.activeWave = waveValue
    state.activeMode = mode
    state.tick = 0
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

    timerLabel.content = "Round timer (raw): " ..
        tostring(timerValue ~= nil and timerValue or "--")

    local newMode = modeValue == 0 and "normal"
        or modeValue == 1 and "hard" or nil

    if not newMode or type(waveValue) ~= "number" then
        return
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

            state.inWave = false
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
updateGameState()
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
