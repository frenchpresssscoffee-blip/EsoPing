PingText = PingText or {}

local PT = PingText

PT.name = "PingText"
PT.title = "Ping Text"
PT.version = "1.4.2"
PT.width = 320
PT.height = 48
PT.defaultFontSize = 18
PT.fastUpdateIntervalMs = 50
PT.currentModeSampleText = "Ping: 9999"
PT.averageModeSampleText = "Ping: 9999 | Avg: 9999"
PT.horizontalPadding = 18
PT.verticalPadding = 16

local defaults = {
    offsetX = 0,
    offsetY = 140,
    anchorMode = "screen",
    unlocked = false,
    fastMode = false,
    smoothingEnabled = false,
    smoothingWindow = 6,
    displayMode = "current",
    fontSize = PT.defaultFontSize,
    cautionLatency = 100,
    warningLatency = 150,
    criticalLatency = 250,
    updateIntervalMs = 100,
    immediateJumpThreshold = 75,
}

local displayModeValues = { "current", "average_current" }
local displayModeLabels = {
    current = "Current Only",
    average_current = "Average + Current",
}

local function Clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    elseif value > maxValue then
        return maxValue
    end

    return value
end

local function BuildChoiceList(labels, values)
    local choices = {}
    for _, value in ipairs(values) do
        table.insert(choices, labels[value])
    end
    return choices
end

local displayModeChoices = BuildChoiceList(displayModeLabels, displayModeValues)

function PT:Print(message)
    local text = string.format("[%s] %s", self.title, tostring(message or ""))
    if CHAT_ROUTER and CHAT_ROUTER.AddSystemMessage then
        CHAT_ROUTER:AddSystemMessage(text)
    else
        local chatBuffer = CHAT_SYSTEM and CHAT_SYSTEM.primaryContainer and CHAT_SYSTEM.primaryContainer.currentBuffer
        if chatBuffer and chatBuffer.AddMessage then
            chatBuffer:AddMessage(text)
        end
    end
end

function PT:GetScreenBounds()
    local width = GuiRoot.GetWidth and GuiRoot:GetWidth() or 0
    local height = GuiRoot.GetHeight and GuiRoot:GetHeight() or 0
    return width, height
end

function PT:GetDefaultPosition()
    local width = select(1, self:GetScreenBounds())
    local offsetX = math.floor(math.max((width - self.width) / 2, 0))
    local offsetY = defaults.offsetY
    return offsetX, offsetY
end

function PT:GetFontString()
    local fontSize = math.max(14, math.floor(tonumber(self.saved and self.saved.fontSize) or PT.defaultFontSize))
    return string.format("$(BOLD_FONT)|%d|soft-shadow-thick", fontSize)
end

function PT:GetChoiceLabel(labels, key, fallbackKey)
    return labels[key] or labels[fallbackKey] or ""
end

function PT:GetKeyFromChoice(labels, choice, fallbackKey)
    for key, label in pairs(labels) do
        if label == choice then
            return key
        end
    end

    return fallbackKey
end

function PT:NormalizeThresholds()
    self.saved.cautionLatency = math.max(1, math.floor(tonumber(self.saved.cautionLatency) or defaults.cautionLatency))
    self.saved.warningLatency = math.max(self.saved.cautionLatency + 1, math.floor(tonumber(self.saved.warningLatency) or defaults.warningLatency))
    self.saved.criticalLatency = math.max(self.saved.warningLatency + 1, math.floor(tonumber(self.saved.criticalLatency) or defaults.criticalLatency))
end

function PT:GetEffectiveUpdateInterval()
    if self.saved.fastMode then
        return self.fastUpdateIntervalMs
    end

    return self.saved.updateIntervalMs
end

function PT:IsSmoothingActive()
    return self.saved.fastMode ~= true and self.saved.smoothingEnabled == true
end

function PT:GetEffectiveDisplayMode()
    return self.saved.displayMode
end

function PT:RefreshVisualSettings()
    if not self.label then
        return
    end

    self:RefreshLayout()
    self.label:SetFont(self:GetFontString())
    self:UpdatePing()
end

function PT:ShouldTrackAverage()
    return self:IsSmoothingActive() or self:GetEffectiveDisplayMode() == "average_current"
end

function PT:GetLayoutMetrics()
    local fontSize = math.max(14, math.floor(tonumber(self.saved and self.saved.fontSize) or PT.defaultFontSize))
    local sampleText = self:GetEffectiveDisplayMode() == "average_current" and self.averageModeSampleText or self.currentModeSampleText
    local width

    if self.measureLabel then
        self.measureLabel:SetFont(string.format("$(BOLD_FONT)|%d|soft-shadow-thick", fontSize))
        self.measureLabel:SetText(sampleText)
        local measuredWidth = select(1, self.measureLabel:GetTextDimensions())
        width = math.floor((measuredWidth or 0) + self.horizontalPadding)
    else
        width = math.floor((string.len(sampleText) * fontSize * 0.60) + self.horizontalPadding)
    end

    local minimumWidth = self:GetEffectiveDisplayMode() == "average_current" and 170 or 110
    width = math.max(minimumWidth, width)
    local height = math.max(32, fontSize + self.verticalPadding)
    return width, height
end

function PT:RefreshLayout()
    local width, height = self:GetLayoutMetrics()
    self.width = width
    self.height = height

    if self.control then
        self.control:SetDimensions(width, height)
    end

    if self.label then
        self.label:SetDimensions(width, height)
    end

    self:SetPosition(self.saved.offsetX or 0, self.saved.offsetY or defaults.offsetY, true)
end

function PT:SetPosition(offsetX, offsetY, silent)
    local screenWidth, screenHeight = self:GetScreenBounds()
    local maxX = math.max(screenWidth - self.width, 0)
    local maxY = math.max(screenHeight - self.height, 0)

    self.saved.offsetX = Clamp(math.floor(tonumber(offsetX) or 0), 0, maxX)
    self.saved.offsetY = Clamp(math.floor(tonumber(offsetY) or 0), 0, maxY)
    self:ApplyAnchor()

    if not silent then
        self:Print(string.format("Position set to (%d, %d).", self.saved.offsetX, self.saved.offsetY))
    end
end

function PT:NudgePosition(direction, amount)
    local distance = math.max(1, math.floor(tonumber(amount) or 20))
    local deltaX = 0
    local deltaY = 0

    if direction == "left" then
        deltaX = -distance
    elseif direction == "right" then
        deltaX = distance
    elseif direction == "up" then
        deltaY = -distance
    elseif direction == "down" then
        deltaY = distance
    else
        return false
    end

    self:SetPosition((self.saved.offsetX or 0) + deltaX, (self.saved.offsetY or 0) + deltaY, true)
    self:Print(string.format("Position nudged %s to (%d, %d).", direction, self.saved.offsetX, self.saved.offsetY))
    return true
end

function PT:SetPresetPosition(preset)
    local screenWidth, screenHeight = self:GetScreenBounds()
    local maxX = math.max(screenWidth - self.width, 0)
    local maxY = math.max(screenHeight - self.height, 0)
    local centerX = math.floor(maxX / 2)
    local centerY = math.floor(maxY / 2)

    if preset == "center" then
        self:SetPosition(centerX, centerY, true)
    elseif preset == "top" then
        self:SetPosition(centerX, defaults.offsetY, true)
    elseif preset == "topleft" then
        self:SetPosition(0, defaults.offsetY, true)
    elseif preset == "topright" then
        self:SetPosition(maxX, defaults.offsetY, true)
    elseif preset == "bottomleft" then
        self:SetPosition(0, maxY, true)
    elseif preset == "bottomright" then
        self:SetPosition(maxX, maxY, true)
    else
        return false
    end

    self:Print(string.format("Position preset set to %s (%d, %d).", preset, self.saved.offsetX, self.saved.offsetY))
    return true
end

function PT:ResetSamples()
    self.samples = {}
    self.sampleTotal = 0
    self.displayedLatency = nil
end

function PT:GetRawLatency()
    return math.floor((GetLatency and GetLatency() or 0) + 0.5)
end

function PT:GetAverageLatency(rawLatency)
    if not self:ShouldTrackAverage() then
        return rawLatency
    end

    self.samples = self.samples or {}
    self.sampleTotal = self.sampleTotal or 0
    table.insert(self.samples, rawLatency)
    self.sampleTotal = self.sampleTotal + rawLatency
    while #self.samples > self.saved.smoothingWindow do
        self.sampleTotal = self.sampleTotal - table.remove(self.samples, 1)
    end

    return math.floor((self.sampleTotal / math.max(#self.samples, 1)) + 0.5)
end

function PT:GetDisplayLatency(rawLatency, averageLatency)
    if not self:IsSmoothingActive() then
        self.displayedLatency = rawLatency
        return rawLatency
    end

    if self.displayedLatency and math.abs(rawLatency - self.displayedLatency) >= self.saved.immediateJumpThreshold then
        self.displayedLatency = rawLatency
        return rawLatency
    end

    self.displayedLatency = averageLatency
    return self.displayedLatency
end

function PT:GetPingColor(displayLatency, rawLatency)
    local latency = math.max(displayLatency or 0, rawLatency or 0)
    if latency >= self.saved.criticalLatency then
        return 1, 0.2, 0.2, 1
    elseif latency >= self.saved.warningLatency then
        return 1, 0.58, 0.12, 1
    elseif latency >= self.saved.cautionLatency then
        return 0.98, 0.86, 0.18, 1
    end

    return 0.32, 0.95, 0.42, 1
end

function PT:GetDisplayText(displayLatency, rawLatency, averageLatency)
    if self:GetEffectiveDisplayMode() == "average_current" then
        return string.format("Ping: %d | Avg: %d", rawLatency, averageLatency)
    end

    return string.format("Ping: %d", displayLatency)
end

function PT:SetLabelColor(red, green, blue, alpha)
    if not self.label then
        return
    end

    local colorKey = string.format("%.3f:%.3f:%.3f:%.3f", red, green, blue, alpha)
    if self.lastColorKey ~= colorKey then
        self.lastColorKey = colorKey
        self.label:SetColor(red, green, blue, alpha)
    end
end

function PT:SetLabelText(text)
    if not self.label then
        return
    end

    if self.lastLabelText ~= text then
        self.lastLabelText = text
        self.label:SetText(text)
    end
end

function PT:SetFastMode(enabled)
    self.saved.fastMode = enabled == true
    self:ResetSamples()
    self:RefreshLayout()
    self:RegisterUpdateLoop()
    self:UpdatePing()
end

function PT:ApplyAnchor()
    if not self.control then
        return
    end

    self.control:ClearAnchors()
    self.control:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, self.saved.offsetX, self.saved.offsetY)
end

function PT:ApplyUnlockedState()
    if not self.control then
        return
    end

    self.control:SetMovable(self.saved.unlocked)
    if self.dragSurface then
        self.dragSurface:SetMouseEnabled(self.saved.unlocked)
        self.dragSurface:SetCenterColor(0, 0, 0, 0)
        self.dragSurface:SetEdgeColor(0, 0, 0, 0)
    end
    if self.label then
        self.label:SetMouseEnabled(self.saved.unlocked)
    end
end

function PT:StartDragging(button)
    if self.saved.unlocked and button == MOUSE_BUTTON_INDEX_LEFT and self.control then
        self.control:StartMoving()
    end
end

function PT:StopDragging(button)
    if button == MOUSE_BUTTON_INDEX_LEFT and self.control then
        self.control:StopMovingOrResizing()
    end
end

function PT:UpdatePing()
    if not self.label then
        return
    end

    local rawLatency = self:GetRawLatency()
    local averageLatency = self:ShouldTrackAverage() and self:GetAverageLatency(rawLatency) or rawLatency
    local displayLatency = self:GetDisplayLatency(rawLatency, averageLatency)
    local red, green, blue, alpha = self:GetPingColor(displayLatency, rawLatency)
    local displayText = self:GetDisplayText(displayLatency, rawLatency, averageLatency)

    self:SetLabelColor(red, green, blue, alpha)
    self:SetLabelText(displayText)
end

function PT:CreateUI()
    local control = WINDOW_MANAGER:CreateTopLevelWindow(self.name .. "Control")
    control:SetDimensions(self.width, self.height)
    control:SetHidden(false)
    control:SetClampedToScreen(true)
    control:SetDrawLayer(DL_OVERLAY)
    control:SetDrawTier(DT_HIGH)
    control:SetMouseEnabled(false)
    control:SetHandler("OnMoveStop", function(window)
        local left, top = window:GetScreenRect()
        self:SetPosition(left or self.saved.offsetX, top or self.saved.offsetY, true)
    end)

    local dragSurface = WINDOW_MANAGER:CreateControl(self.name .. "DragSurface", control, CT_BACKDROP)
    dragSurface:SetAnchorFill(control)
    dragSurface:SetCenterTexture("EsoUI/Art/Miscellaneous/blank.dds")
    dragSurface:SetEdgeTexture("EsoUI/Art/Miscellaneous/blank.dds", 1, 1, 1)
    dragSurface:SetInsets(0, 0, 0, 0)
    dragSurface:SetCenterColor(0, 0, 0, 0)
    dragSurface:SetEdgeColor(0, 0, 0, 0)
    dragSurface:SetMouseEnabled(false)
    dragSurface:SetHandler("OnMouseDown", function(_, button)
        self:StartDragging(button)
    end)
    dragSurface:SetHandler("OnMouseUp", function(_, button)
        self:StopDragging(button)
    end)

    local label = WINDOW_MANAGER:CreateControl(self.name .. "Label", control, CT_LABEL)
    label:SetAnchor(CENTER, control, CENTER, 0, 0)
    label:SetDimensions(self.width, self.height)
    label:SetFont(self:GetFontString())
    label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    label:SetMouseEnabled(false)
    label:SetHandler("OnMouseDown", function(_, button)
        self:StartDragging(button)
    end)
    label:SetHandler("OnMouseUp", function(_, button)
        self:StopDragging(button)
    end)
    label:SetText("Ping: --")

    local measureLabel = WINDOW_MANAGER:CreateControl(self.name .. "MeasureLabel", control, CT_LABEL)
    measureLabel:SetHidden(true)
    measureLabel:SetDimensions(1, 1)
    measureLabel:SetFont(self:GetFontString())
    measureLabel:SetText("")

    self.control = control
    self.dragSurface = dragSurface
    self.label = label
    self.measureLabel = measureLabel
    self:ApplyAnchor()
    self:ApplyUnlockedState()
end

function PT:RegisterUpdateLoop()
    EVENT_MANAGER:UnregisterForUpdate(self.name .. "Update")
    EVENT_MANAGER:RegisterForUpdate(self.name .. "Update", self:GetEffectiveUpdateInterval(), function()
        self:UpdatePing()
    end)
end

function PT:PrintStatus()
    self:Print(string.format(
        "mode=%s size=%d fast=%s smoothing=%s unlocked=%s caution=%d warning=%d critical=%d interval=%d pos=(%d,%d)",
        self:GetEffectiveDisplayMode(),
        self.saved.fontSize,
        tostring(self.saved.fastMode),
        tostring(self.saved.smoothingEnabled),
        tostring(self.saved.unlocked),
        self.saved.cautionLatency,
        self.saved.warningLatency,
        self.saved.criticalLatency,
        self:GetEffectiveUpdateInterval(),
        self.saved.offsetX,
        self.saved.offsetY
    ))
end

function PT:RegisterSettingsPanel()
    if self.settingsRegistered then
        return
    end

    local LAM2 = LibAddonMenu2
    if not LAM2 then
        return
    end

    local panelId = self.name .. "Settings"
    local panelData = {
        type = "panel",
        name = self.title,
        displayName = self.title,
        author = "PingText",
        version = self.version,
        registerForDefaults = true,
        registerForRefresh = true,
    }

    local options = {
        {
            type = "description",
            text = "Shows your latency as plain text with color bands, optional smoothing, and average/current display modes.",
        },
        {
            type = "checkbox",
            name = "Fast Mode",
            tooltip = "Poll at 50ms and bypass smoothing for quicker updates. Your chosen display mode still applies.",
            getFunc = function() return self.saved.fastMode end,
            setFunc = function(value)
                self:SetFastMode(value)
            end,
            default = defaults.fastMode,
        },
        {
            type = "checkbox",
            name = "Unlock Position",
            tooltip = "Enable dragging with the left mouse button.",
            getFunc = function() return self.saved.unlocked end,
            setFunc = function(value)
                self.saved.unlocked = value == true
                self:ApplyUnlockedState()
            end,
            default = defaults.unlocked,
        },
        {
            type = "dropdown",
            name = "Display Mode",
            tooltip = "Choose whether to show only the current ping or both current and moving average.",
            choices = displayModeChoices,
            getFunc = function()
                return self:GetChoiceLabel(displayModeLabels, self.saved.displayMode, defaults.displayMode)
            end,
            setFunc = function(choice)
                self.saved.displayMode = self:GetKeyFromChoice(displayModeLabels, choice, defaults.displayMode)
                self:ResetSamples()
                self:RefreshLayout()
                self:UpdatePing()
            end,
            default = self:GetChoiceLabel(displayModeLabels, defaults.displayMode, defaults.displayMode),
        },
        {
            type = "slider",
            name = "Font Size",
            tooltip = "Adjust the on-screen text size.",
            min = 14,
            max = 36,
            step = 1,
            getFunc = function() return self.saved.fontSize end,
            setFunc = function(value)
                self.saved.fontSize = math.floor(value)
                self:RefreshVisualSettings()
            end,
            default = defaults.fontSize,
        },
        {
            type = "checkbox",
            name = "Enable Smoothing",
            tooltip = "Use a short moving average to reduce flicker.",
            getFunc = function() return self.saved.smoothingEnabled end,
            setFunc = function(value)
                self.saved.smoothingEnabled = value == true
                self:ResetSamples()
                self:UpdatePing()
            end,
            default = defaults.smoothingEnabled,
        },
        {
            type = "slider",
            name = "Green/Yellow Threshold",
            tooltip = "Ping at or above this value turns yellow.",
            min = 25,
            max = 300,
            step = 5,
            getFunc = function() return self.saved.cautionLatency end,
            setFunc = function(value)
                self.saved.cautionLatency = math.floor(value)
                self:NormalizeThresholds()
                self:UpdatePing()
            end,
            default = defaults.cautionLatency,
        },
        {
            type = "slider",
            name = "Yellow/Orange Threshold",
            tooltip = "Ping at or above this value turns orange.",
            min = 50,
            max = 500,
            step = 5,
            getFunc = function() return self.saved.warningLatency end,
            setFunc = function(value)
                self.saved.warningLatency = math.floor(value)
                self:NormalizeThresholds()
                self:UpdatePing()
            end,
            default = defaults.warningLatency,
        },
        {
            type = "slider",
            name = "Orange/Red Threshold",
            tooltip = "Ping at or above this value turns red.",
            min = 75,
            max = 1000,
            step = 5,
            getFunc = function() return self.saved.criticalLatency end,
            setFunc = function(value)
                self.saved.criticalLatency = math.floor(value)
                self:NormalizeThresholds()
                self:UpdatePing()
            end,
            default = defaults.criticalLatency,
        },
        {
            type = "button",
            name = "Reset Position",
            tooltip = "Move the ping text back to its default location.",
            func = function()
                local defaultX, defaultY = self:GetDefaultPosition()
                self:SetPosition(defaultX, defaultY, true)
                self:Print("Ping text position reset.")
            end,
            width = "half",
        },
    }

    LAM2:RegisterAddonPanel(panelId, panelData)
    LAM2:RegisterOptionControls(panelId, options)
    self.settingsRegistered = true
end

function PT:HandleSlashCommand(text)
    local command, argument = string.match(text or "", "^%s*(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")
    local value = tonumber(argument)
    local argOne, argTwo = string.match(argument or "", "^%s*(%-?%d+)%s+(%-?%d+)%s*$")
    local wordOne, wordTwo = string.match(argument or "", "^%s*(%S+)%s*(.-)%s*$")
    local loweredArgument = string.lower(argument or "")

    if command == "" or command == "status" then
        self:PrintStatus()
    elseif command == "fast" then
        self:SetFastMode(not self.saved.fastMode)
        self:Print(self.saved.fastMode and "Fast mode enabled. Polling is now 50ms and smoothing is bypassed." or "Fast mode disabled.")
    elseif command == "unlock" or command == "move" then
        self.saved.unlocked = not self.saved.unlocked
        self:ApplyUnlockedState()
        self:Print(self.saved.unlocked and "Move mode enabled. Drag the ping text with the left mouse button." or "Move mode disabled.")
    elseif command == "smooth" then
        self.saved.smoothingEnabled = not self.saved.smoothingEnabled
        self:ResetSamples()
        self:UpdatePing()
        self:Print(self.saved.smoothingEnabled and "Ping smoothing enabled." or "Ping smoothing disabled.")
    elseif command == "reset" then
        local defaultX, defaultY = self:GetDefaultPosition()
        self:SetPosition(defaultX, defaultY, true)
        self:Print("Ping text position reset.")
    elseif command == "pos" and argOne and argTwo then
        self:SetPosition(argOne, argTwo, false)
    elseif command == "nudge" and wordOne ~= nil and wordOne ~= "" then
        if not self:NudgePosition(string.lower(wordOne), tonumber(wordTwo)) then
            self:Print("Usage: /pingtext nudge <left|right|up|down> [amount]")
        end
    elseif command == "preset" and wordOne ~= nil and wordOne ~= "" then
        if not self:SetPresetPosition(string.lower(wordOne)) then
            self:Print("Usage: /pingtext preset <top|topleft|topright|center|bottomleft|bottomright>")
        end
    elseif command == "display" and loweredArgument ~= "" then
        if loweredArgument == "average" or loweredArgument == "avg" then
            loweredArgument = "average_current"
        end
        if displayModeLabels[loweredArgument] then
            self.saved.displayMode = loweredArgument
            self:ResetSamples()
            self:RefreshLayout()
            self:UpdatePing()
            self:Print("Display mode set to " .. self.saved.displayMode .. ".")
        else
            self:Print("Usage: /pingtext display <current|average>")
        end
    elseif command == "size" and value then
        self.saved.fontSize = Clamp(math.floor(value), 14, 36)
        self:RefreshVisualSettings()
        self:Print("Font size set to " .. tostring(self.saved.fontSize) .. ".")
    elseif command == "caution" and value then
        self.saved.cautionLatency = math.max(1, math.floor(value))
        self:NormalizeThresholds()
        self:UpdatePing()
        self:Print("Caution threshold set to " .. tostring(self.saved.cautionLatency) .. " ms.")
    elseif command == "warn" and value then
        self.saved.warningLatency = math.max(1, math.floor(value))
        self:NormalizeThresholds()
        self:UpdatePing()
        self:Print("Warning threshold set to " .. tostring(self.saved.warningLatency) .. " ms.")
    elseif command == "critical" and value then
        self.saved.criticalLatency = math.floor(value)
        self:NormalizeThresholds()
        self:UpdatePing()
        self:Print("Critical threshold set to " .. tostring(self.saved.criticalLatency) .. " ms.")
    else
        self:Print("Commands: /pingtext status, /pingtext fast, /pingtext unlock, /pingtext smooth, /pingtext reset, /pingtext pos <x> <y>, /pingtext nudge <left|right|up|down> [amount], /pingtext preset <top|topleft|topright|center|bottomleft|bottomright>, /pingtext display <current|average>, /pingtext size <14-36>, /pingtext caution <ms>, /pingtext warn <ms>, /pingtext critical <ms>")
    end
end

function PT:Initialize()
    self.saved = ZO_SavedVars:NewAccountWide("PingTextSavedVars", 1, GetWorldName(), defaults)
    local defaultX, defaultY = self:GetDefaultPosition()
    local legacyOffsetX = math.floor(tonumber(self.saved.offsetX) or defaults.offsetX)
    local legacyOffsetY = math.floor(tonumber(self.saved.offsetY) or defaults.offsetY)
    if self.saved.anchorMode ~= "screen" then
        local screenWidth = select(1, self:GetScreenBounds())
        self.saved.offsetX = math.floor((screenWidth / 2) + legacyOffsetX - (self.width / 2))
        self.saved.offsetY = legacyOffsetY
        self.saved.anchorMode = "screen"
    else
        self.saved.offsetX = legacyOffsetX
        self.saved.offsetY = legacyOffsetY
    end
    self.saved.unlocked = self.saved.unlocked == true
    self.saved.fastMode = self.saved.fastMode == true
    self.saved.smoothingEnabled = self.saved.smoothingEnabled == true
    self.saved.smoothingWindow = math.max(2, math.floor(tonumber(self.saved.smoothingWindow) or defaults.smoothingWindow))
    self.saved.displayMode = displayModeLabels[self.saved.displayMode] and self.saved.displayMode or defaults.displayMode
    self.saved.fontSize = Clamp(math.floor(tonumber(self.saved.fontSize) or defaults.fontSize), 14, 36)
    self.saved.cautionLatency = math.max(1, math.floor(tonumber(self.saved.cautionLatency) or defaults.cautionLatency))
    self.saved.warningLatency = math.max(1, math.floor(tonumber(self.saved.warningLatency) or defaults.warningLatency))
    self.saved.criticalLatency = math.max(1, math.floor(tonumber(self.saved.criticalLatency) or defaults.criticalLatency))
    self:NormalizeThresholds()
    self.saved.updateIntervalMs = math.max(50, math.floor(tonumber(self.saved.updateIntervalMs) or defaults.updateIntervalMs))
    self.saved.immediateJumpThreshold = math.max(1, math.floor(tonumber(self.saved.immediateJumpThreshold) or defaults.immediateJumpThreshold))
    self:ResetSamples()
    self:CreateUI()
    self:SetPosition(self.saved.offsetX or defaultX, self.saved.offsetY or defaultY, true)
    self:RefreshVisualSettings()
    self:UpdatePing()
    self:RegisterUpdateLoop()
    self:RegisterSettingsPanel()

    SLASH_COMMANDS["/pingtext"] = function(text)
        self:HandleSlashCommand(text)
    end
    SLASH_COMMANDS["/pt"] = SLASH_COMMANDS["/pingtext"]
end

local function OnAddOnLoaded(_, addonName)
    if addonName ~= PT.name then
        return
    end

    EVENT_MANAGER:UnregisterForEvent(PT.name, EVENT_ADD_ON_LOADED)
    PT:Initialize()
end

EVENT_MANAGER:RegisterForEvent(PT.name, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
