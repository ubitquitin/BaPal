
local parent = ui.Interfaces:GetComponent(
    id.Component.TOPLEVEL_V2__GAME_AREA
)

local ba_app = prettyui.Window.new(parent, {
    title = "BA Pal",
    x = 149,
    y = 336,
    width = 440,
    height = 440,
    minWidth = 340,
    minHeight = 300,
    rowBackgroundColours = {
        0x24211EFF,
        0x2E2825FF
    },
    resizable = true
})

-- =====================================
-- Varplayers
-- =====================================

local function vp(id)
    local config = var.VarPlayer.FromID(id)
    return config and config.value or nil
end

local FLAGS_ID = 4689
local TIMER_ID = 4690

local waveFlags = {
    normal = {
        [2] = 0x2, [3] = 0x4,
        [4] = 0x8, [5] = 0x10,
        [6] = 0x20, [7] = 0x40,
        [8] = 0x80, [9] = 0x100,
        [10] = 0x200
    },
    hard = {
        [1] = 0x400, [2] = 0x800,
        [3] = 0x1000, [4] = 0x2000,
        [5] = 0x4000, [6] = 0x8000,
        [7] = 0x10000, [8] = 0x20000,
        [9] = 0x40000, [10] = 0x80000
    }
}

local function flagSet(value, mask)
    return mask ~= nil and (value & mask) ~= 0
end

-- =====================================
-- State
-- =====================================

local tick = 0
local selectedMode = "normal"
local previousFlags = nil
local previousTimer = nil

local splits = {
    normal = {},
    hard = {}
}

local roleNames = {
    [0] = "Attacker",
    [1] = "Defender",
    [2] = "Collector",
    [3] = "Healer"
}

-- =====================================
-- Tabs
-- =====================================

local tabs = ba_app:AddTabs({
    { text = "Wave Splits" },
    { text = "Wave Tick" }
}, {
    height = 265,
    activeIndex = 1
})

local splitPage = tabs:GetPage(1)
local tickPage = tabs:GetPage(2)

-- =====================================
-- Wave Splits page
-- =====================================

splitPage:AddText("Display mode:")

local modeLabel = splitPage:AddText({
    text = "Normal",
    colour = 0xE8BD83FF
})

local rows = {}

local function formatTime(value)
    if value == nil then
        return "--:--"
    end

    -- Assumes value is seconds.
    -- Adjust after verifying timer units.
    local seconds = math.floor(value)
    return string.format(
        "%02d:%02d",
        math.floor(seconds / 60),
        seconds % 60
    )
end

local function refreshSplits()
    modeLabel.content =
        selectedMode == "hard" and "Hard" or "Normal"

    for wave = 1, 9 do
        local value = splits[selectedMode][wave]

        rows[wave].content = string.format(
            "Wave %d     %s",
            wave,
            formatTime(value)
        )
    end
end

splitPage:AddSimpleButton("Normal / Hard", function()
    selectedMode =
        selectedMode == "normal" and "hard" or "normal"
    refreshSplits()
end)

splitPage:AddText({
    text = "WAVE          TIME",
    colour = 0xE8BD83FF
})

for wave = 1, 9 do
    rows[wave] = splitPage:AddText({
        text = string.format("Wave %d     --:--", wave),
        height = 20
    })
end

-- =====================================
-- Wave Tick page
-- =====================================

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

-- =====================================
-- Player information footer
-- =====================================

ba_app:AddText({
    text = "PLAYER INFORMATION",
    colour = 0xE8BD83FF,
    marginTop = 8
})

local roleLabel = ba_app:AddText("Role: --")

local pointsLabel = ba_app:AddText({
    text = "Points: --",
    height = 24
})

local teammatesLabel = ba_app:AddText({
    text = "Teammates: --",
    height = 24
})

-- =====================================
-- Player info updates
-- =====================================

local function updatePlayerInfo()
    local role = vp(1494)

    roleLabel.content =
        "Role: " .. (roleNames[role] or tostring(role or "--"))

    local attacker = vp(1495)
    local defender = vp(1496)
    local collector = vp(1497)
    local healer = vp(1498)

    pointsLabel.content = string.format(
        "A: %s  D: %s  C: %s  H: %s",
        tostring(attacker or "--"),
        tostring(defender or "--"),
        tostring(collector or "--"),
        tostring(healer or "--")
    )

    local teammates = {}

    for id = 1499, 1502 do
        local uid = vp(id)
        if uid ~= nil and uid ~= 0 then
            teammates[#teammates + 1] = tostring(uid)
        end
    end

    teammatesLabel.content =
        "Teammates: " .. (
            #teammates > 0
            and table.concat(teammates, ", ")
            or "--"
        )
end

-- =====================================
-- Wave flag tracking
-- =====================================

local function updateWaves()
    local flags = vp(FLAGS_ID)
    local timer = vp(TIMER_ID)

    if flags == nil or timer == nil then
        return
    end

    timerLabel.content =
        "Round timer (raw): " .. tostring(timer)

    if previousFlags ~= nil then
        for _, mode in ipairs({ "normal", "hard" }) do
            for wave = 1, 9 do
                local mask = waveFlags[mode][wave]

                if mask then
                    local wasSet = flagSet(previousFlags, mask)
                    local isSet = flagSet(flags, mask)

                    if isSet and not wasSet then
                        -- A wave flag has transitioned.
                        --
                        -- Do not assign a split yet:
                        -- 4690 timer semantics and
                        -- flag timing must be verified.
                        --
                        -- Debug logging:
                        log(string.format(
                            "BA wave flag: mode=%s wave=%d timer=%s",
                            mode, wave, tostring(timer)
                        ))
                    end
                end
            end
        end
    end

    previousFlags = flags
    previousTimer = timer
end

-- =====================================
-- Server tick
-- =====================================

Event.ServerLogic.Subscribe("serverLogicEvent", function()
    tickLabel.content = tostring(tick)
    tick = (tick + 1) % 10

    updateWaves()
    updatePlayerInfo()
end)

refreshSplits()
updatePlayerInfo()
ba_app:RefreshRowBackgrounds()

-- Merge with any existing shutdown function.
function PluginShutdown()
    Event.ServerLogic.Unsubscribe("serverLogicEvent")
    ba_app:Destroy()
end
