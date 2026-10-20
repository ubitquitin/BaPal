
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

local function vc(id)
    local ok, value = pcall(function()
        local config = var.VarClient.FromID(id)
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

local TEAM_NAME_IDS = {
    2435, 2436, 2437, 2438, 2439
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

    currentMode = nil,
    currentWave = nil,

    previousMode = nil,
    previousWave = nil,
    previousTimer = nil,

    splits = {
        normal = {},
        hard = {}
    }
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
    text = "WAVE          TIME",
    colour = 0xE8BD83FF
})

local splitRows = {}

for wave = 1, 9 do
    splitRows[wave] = splitPage:AddText({
        text = string.format(
            "Wave %d     --:--",
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

    modeLabel.content =
        "Mode: " .. (
            mode == "hard" and "Hard"
            or mode == "normal" and "Normal"
            or "--"
        )

    waveLabel.content =
        "Current Wave: " ..
        tostring(state.currentWave or "--")

    for wave = 1, 9 do
        local time = mode
            and state.splits[mode][wave]
            or nil

        splitRows[wave].content = string.format(
            "Wave %d     %s",
            wave,
            formatTime(time)
        )
    end
end

-- ============================================
-- Wave Tick UI
-- ============================================

tickPage:AddTitle("Current Tick")

local tickLabel = tickPage:AddText({
    text = "0",
    colour = 0xE8BD83FF,
    height = 50
})

tickPage:AddText("Repeats every 10 server ticks")

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

ba_app:AddText({
    text = "Team",
    colour = 0xE8BD83FF
})

local teammatesLabel = ba_app:AddText({
    text = "Teammates: --",
    height = 40
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

    local names = {}
    local seen = {}

    for _, id in ipairs(TEAM_NAME_IDS) do
        local name = vc(id)

        if type(name) == "string" then
            name = name:match("^%s*(.-)%s*$")

            if name ~= "" and not seen[name] then
                names[#names + 1] = name
                seen[name] = true
            end
        end
    end

    teammatesLabel.content =
        "Team: " .. (
            #names > 0
            and table.concat(names, ", ")
            or "--"
        )
end

-- ============================================
-- Game State / Wave Tracking
-- ============================================

local function updateGameState()
    local modeValue = vp(VAR.MODE)
    local waveValue = vp(VAR.WAVE)
    local timerValue = vp(VAR.ROUND_TIME)

    -- Update raw timer independently.
    timerLabel.content =
        "Round timer (raw): " ..
        tostring(timerValue or "--")

    if modeValue == nil or waveValue == nil then
        return
    end

    local newMode = nil

    if modeValue == 0 then
        newMode = "normal"
    elseif modeValue == 1 then
        newMode = "hard"
    end

    if newMode == nil then
        return
    end

    local modeChanged =
        newMode ~= state.currentMode

    local waveChanged =
        waveValue ~= state.currentWave

    -- Initial observation: do not record a split.
    if state.currentWave == nil then
        state.currentMode = newMode
        state.currentWave = waveValue
        state.previousTimer = timerValue

        refreshSplits()
        return
    end

    -- Detect wave transitions.
    if waveChanged then
        local oldWave = state.currentWave
        local oldMode = state.currentMode

        print(string.format(
            "BA wave transition: %s -> %s",
            tostring(oldWave),
            tostring(waveValue)
        ))

        -- A sequential increment is a candidate
        -- completed-wave event.
        --
        -- Note: ticket skips may also increment
        -- the wave number, so this needs validation.
        if waveValue == oldWave + 1
            and oldWave >= 1
            and oldWave <= 9
            and oldMode == newMode then

            local completedTime = nil

            if SPLIT_TIMER_SOURCE == "previous" then
                completedTime = state.previousTimer
            else
                completedTime = timerValue
            end

            if completedTime ~= nil then
                state.splits[oldMode][oldWave] =
                    completedTime

                print(string.format(
                    "BA split: mode=%s wave=%d time=%s",
                    oldMode,
                    oldWave,
                    tostring(completedTime)
                ))
            end
        end
    end

    state.currentMode = newMode
    state.currentWave = waveValue
    state.previousTimer = timerValue

    if modeChanged or waveChanged then
        refreshSplits()
    end

    tickWaveLabel.content =
        "Wave: " .. tostring(waveValue)

    tickModeLabel.content =
        "Mode: " .. (
            newMode == "hard" and "Hard"
            or "Normal"
        )
end

-- ============================================
-- Server Tick
-- ============================================

Event.ServerLogic.Subscribe(
    "serverLogicEvent",
    function()
        tickLabel.content = tostring(state.tick)
        state.tick = (state.tick + 1) % 10

        updateGameState()
        updatePlayerInfo()
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

    ba_app:Destroy()
end
