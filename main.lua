
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

local function vc(id)
    local ok, value = pcall(function()
        local config = var.VarClient.FromID(id)
        return config and config.value or nil
    end)
    return ok and value or nil
end

local VAR = {
    MODE = 4688,
    WAVE_HINT = -22919, -- ticket/lobby hint only; not wave-completion signal
    GAMEAREA_MASTER = 1776,
    ROUND_TIME = 4690,
    ROLE = 1494,
    KING_KILL_CURRENCY = -22920,
    QUEEN_TICKET_BLOCK = 4840, -- change heuristic only
    QUEEN_KILLED = -4509, -- observe changes for a queen kill
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
    lastGamearea = nil,
    gameareaChanges = 0,
    waveCounter = 0,
    lastCallValue = nil,
    lastCallTick = nil,

    -- GAMEAREA_MASTER transitions toggle ordinary waves; startup can seed via IsRegion.
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
    kingFoodStartTick = nil,
    queenStored = nil,
    lastQueenBlock = nil,
    lastQueenKilled = nil
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

-- BARBASSAULT3's numeric ID was not supplied. Prefer the named
-- config when available; set BARBASSAULT3_ID below if needed.
local BARBASSAULT3_ID = nil
local function readCallVariable()
    if BARBASSAULT3_ID then return vp(BARBASSAULT3_ID) end
    local ok, value = pcall(function()
        local config = var.Player.BARBASSAULT3
        return config and config.value or nil
    end)
    return ok and value or nil
end

local function updateWaveTimers()
    if state.inWave and state.waveStartTick ~= nil then
        local elapsed = math.max(0, state.serverTick - state.waveStartTick)
        state.waveElapsedTicks = elapsed
        timerLabel.content = "Wave time (ticks): " .. tostring(elapsed)
        if state.lastCallTick ~= nil then
            local sinceCall = math.max(0, state.serverTick - state.lastCallTick)
            local remain = math.max(0, CALL_CHANGE_TICKS - sinceCall)
            callChangeLabel.content = string.format("Call change in: %.1fs", remain * SECONDS_PER_GAME_TICK)
        else
            callChangeLabel.content = "Call change in: -- (awaiting BARBASSAULT3)"
        end
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

local KING_SPAWN_TICKS = 600  -- 6 minutes at 600 ms per server tick
local KING_FOOD_TICKS = 36
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
    local queenBlock = vp(VAR.QUEEN_TICKET_BLOCK)
    local queenKilled = vp(VAR.QUEEN_KILLED)

    -- Heuristic: a change in the queen-killed flag indicates a new kill;
    -- a change in ticket block indicates a possible redemption.
    -- Prioritize kill if both change in the same server tick.
    local blockChanged = queenBlock ~= nil and state.lastQueenBlock ~= nil
        and queenBlock ~= state.lastQueenBlock
    local killChanged = queenKilled ~= nil and state.lastQueenKilled ~= nil
        and queenKilled ~= state.lastQueenKilled
    if blockChanged then
        state.queenStored = 0
        print("BA queen ticket block changed: " .. tostring(state.lastQueenBlock)
            .. " -> " .. tostring(queenBlock))
    end
    if killChanged then
        state.queenStored = 1
        print("BA queen killed flag changed: " .. tostring(state.lastQueenKilled)
            .. " -> " .. tostring(queenKilled))
    end
    if queenBlock ~= nil then state.lastQueenBlock = queenBlock end
    if queenKilled ~= nil then state.lastQueenKilled = queenKilled end
    kingKillsLabel.content = "King kills: " .. tostring(kingKills ~= nil and kingKills or "--") .. " / 50"
    queenKillsLabel.content = "Queen kills: " .. tostring(state.queenStored ~= nil and state.queenStored or "--") .. " / 1"
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

local function updateKing()
    if not state.kingActive then return end

    local elapsed = math.max(0, state.serverTick - state.kingStartTick)
    local remaining = math.max(0, KING_SPAWN_TICKS - elapsed)
    local seconds = math.ceil(remaining * 0.6)
    local colour = remaining <= 50 and "red"
        or remaining <= 100 and "yellow" or "green"
    showKingTimer(string.format("%02d:%02d",
        math.floor(seconds / 60), seconds % 60), colour)

    -- The 36-tick timer is started exclusively by the King chat announcement.
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

ba_app:AddText({ text = "TEAMMATES", colour = 0xE8BD83FF, marginTop = 8 })
local teamLabels = {}
for slot = 1, 5 do
    teamLabels[slot] = ba_app:AddText({
        text = string.format("%d. --", slot), height = 21,
        marginTop = 0, marginBottom = 0
    })
end

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

    for slot = 1, 5 do
        local value = vc(2434 + slot)
        local name = type(value) == "string" and value:match("^%s*(.-)%s*$") or nil
        teamLabels[slot].content = string.format("%d. %s", slot,
            name and name ~= "" and name or "--")
    end


end

-- ============================================
-- Game State / Wave Tracking
-- ============================================

local function resetRun()
    resetKing()
    state.splits = { normal = {}, hard = {} }
    state.quickstarts = { normal = {}, hard = {} }
    state.waveCounter = 0
    state.inWave = false
    state.activeWave = nil
    state.activeMode = nil
    state.tick = 0
    state.waveStartTick = nil
    state.waveElapsedTicks = nil
    state.lastCallTick = nil
    state.lastCallValue = nil
    state.quickstartStartTick = nil
    state.quickstartTargetWave = nil
    state.quickstartMode = nil
    tickLabel.content = "--"
    tickStatusLabel.content = "Status: Waiting for wave"
    updateWaveTimers()
end

local function modeNow()
    local v = vp(VAR.MODE)
    return v == 1 and "hard" or v == 0 and "normal" or nil
end

local function startWave()
    if state.inWave then return end
    local mode = modeNow()
    if not mode then return end
    -- Wave numbers 1-9 are inferred from sequential starts; the old
    -- -22919 variable is not used to decide whether a wave ended.
    local wave = state.waveCounter + 1
    if wave > 9 then
        resetRun()
        wave = 1
    end
    state.waveCounter = wave
    state.currentWave = wave
    state.currentMode = mode
    if state.quickstartStartTick and wave > 1 then
        state.quickstarts[mode][wave - 1] =
            state.serverTick - state.quickstartStartTick
    end
    state.quickstartStartTick = nil
    state.inWave = true
    state.activeWave = wave
    state.activeMode = mode
    state.tick = 0
    state.waveStartTick = state.serverTick
    state.waveElapsedTicks = 0
    state.lastCallValue = readCallVariable()
    state.lastCallTick = state.lastCallValue ~= nil and state.serverTick or nil
    tickLabel.content = "0"
    tickStatusLabel.content = "Status: In wave"
    updateWaveTimers()
    refreshSplits()
    print("BA wave START from GAMEAREA_MASTER: " .. tostring(wave))
end

local function endWave()
    if not state.inWave then return end
    local elapsed = math.max(0, state.serverTick - state.waveStartTick)
    state.waveElapsedTicks = elapsed
    if state.activeWave and state.activeWave <= 9 then
        state.splits[state.activeMode][state.activeWave] = elapsed
    end
    state.inWave = false
    state.waveStartTick = nil
    state.lastCallTick = nil
    state.lastCallValue = nil
    state.quickstartStartTick = state.serverTick
    state.activeWave = nil
    state.activeMode = nil
    state.tick = 0
    tickLabel.content = "--"
    tickStatusLabel.content = "Status: Between waves"
    updateWaveTimers()
    refreshSplits()
    print("BA wave END from GAMEAREA_MASTER")
end

local function updateGameState()
    local mode = modeNow()
    local gamearea = vp(VAR.GAMEAREA_MASTER)
    local hint = vp(VAR.WAVE_HINT)
    tickModeLabel.content = "Mode: " .. (mode == "hard" and "Hard" or mode == "normal" and "Normal" or "--")
    tickWaveLabel.content = "Wave (inferred): " .. tostring(state.currentWave or "--")
    if mode then state.currentMode = mode end
    -- First read establishes the baseline. If loaded mid-instance,
    -- seed active state so the next 1776 change correctly ends the wave.
    if state.lastGamearea == nil and gamearea ~= nil then
        local ok, inRegion = pcall(function() return World.IsRegion() end)
        if ok and inRegion and mode then
            if mode == "hard" and hint == 10 then
                startKing()
            else
                startWave()
                print("BA startup: initialized active wave from World.IsRegion()")
            end
        end
    end
    if gamearea ~= nil then
        if state.lastGamearea ~= nil and gamearea ~= state.lastGamearea then
            state.gameareaChanges = state.gameareaChanges + 1
            print("GAMEAREA_MASTER: " .. tostring(state.lastGamearea) .. " -> " .. tostring(gamearea))
            -- Until we identify the precise entry/exit values, toggle on
            -- each transition. See the calibration note in the response.
            if state.inWave then
                endWave()
            elseif state.kingActive then
                resetKing()
            elseif mode and not (mode == "hard" and hint == 10) then
                startWave()
            end
        end
        state.lastGamearea = gamearea
    end
    -- Call changes are observed independently of wave boundaries.
    if state.inWave then
        local callValue = readCallVariable()
        if callValue ~= nil then
            if state.lastCallValue ~= nil and callValue ~= state.lastCallValue then
                state.lastCallTick = state.serverTick
                print("BA call changed: " .. tostring(state.lastCallValue) .. " -> " .. tostring(callValue))
            elseif state.lastCallValue == nil then
                state.lastCallTick = state.serverTick
            end
            state.lastCallValue = callValue
        end
    end
    refreshSplits()
end

-- RegionCreated remains useful for the confirmed hard-mode King entry.
local function startWaveFromRegion()
    if modeNow() == "hard" and vp(VAR.WAVE_HINT) == 10 then
        if state.inWave then endWave() end
        startKing()
    end
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

-- Requires chatAccess permission in the plugin manifest.
-- Match the actual in-game announcement text if it differs.
local chatSubscribed = pcall(function()
    Event.ChatMessage.Subscribe("baKingAnnouncement", function(event)
        if not state.kingActive or state.kingSpawnDetected then return end
        local msg = tostring(event.chatMessage or "")
        local plain = msg:gsub("<[^>]*>", ""):lower()
        if plain:find("penance king", 1, true)
            and (plain:find("appear", 1, true)
                or plain:find("spawn", 1, true)
                or plain:find("emerge", 1, true)) then
            state.kingSpawnDetected = true
            state.kingFoodStartTick = state.serverTick
            kingStatusLabel.content = "King announcement detected"
            print("BA King food timer started by chat: " .. plain)
        end
    end)
end)

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

    if chatSubscribed then
        pcall(function() Event.ChatMessage.Unsubscribe("baKingAnnouncement") end)
    end
    ba_app:Destroy()
end
