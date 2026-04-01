local ADDON_NAME = "SimplePing"
local ADDON_VERSION = "1.1.0"
local SAVED_VARS_VERSION = 1

local LEFT_MOUSE_BUTTON = MOUSE_BUTTON_INDEX_LEFT or 1

local CONSTANTS = {
    CONTROL_WIDTH = 200,
    CONTROL_HEIGHT = 40,

    DEFAULT_POS_POINT = TOP,
    DEFAULT_POS_RELATIVE_POINT = TOP,
    DEFAULT_POS_OFFSET_X = 0,
    DEFAULT_POS_OFFSET_Y = 10,

    DEFAULT_UPDATE_INTERVAL_MS = 500,
    MIN_UPDATE_INTERVAL_MS = 100,
    MAX_UPDATE_INTERVAL_MS = 5000,
    UPDATE_INTERVAL_STEP_MS = 100,

    DEFAULT_THRESHOLD_GOOD = 100,
    DEFAULT_THRESHOLD_BAD = 200,
    MIN_THRESHOLD = 50,
    MAX_THRESHOLD_GOOD = 300,
    MAX_THRESHOLD_BAD = 500,
    THRESHOLD_STEP = 10,

    DEFAULT_FONT_SIZE = 18,
    MIN_FONT_SIZE = 12,
    MAX_FONT_SIZE = 32,
    FONT_SIZE_STEP = 1,

    GetColorGoodDefault = function() return { r = 0, g = 1, b = 0, a = 1 } end,
    GetColorMediumDefault = function() return { r = 1, g = 1, b = 0, a = 1 } end,
    GetColorBadDefault = function() return { r = 1, g = 0, b = 0, a = 1 } end,

    MIN_OFFSET = -5000,
    MAX_OFFSET = 5000,
}

-- Font strings cache (must be before ViewModule)
local FONT_STRINGS = {}
for size = CONSTANTS.MIN_FONT_SIZE, CONSTANTS.MAX_FONT_SIZE do
    FONT_STRINGS[size] = string.format("$(BOLD_FONT)|$(KB_%d)", size)
end

local DEFAULTS = {
    posPoint = CONSTANTS.DEFAULT_POS_POINT,
    posRelativePoint = CONSTANTS.DEFAULT_POS_RELATIVE_POINT,
    posOffsetX = CONSTANTS.DEFAULT_POS_OFFSET_X,
    posOffsetY = CONSTANTS.DEFAULT_POS_OFFSET_Y,
    updateInterval = CONSTANTS.DEFAULT_UPDATE_INTERVAL_MS,
    colorGood = CONSTANTS.GetColorGoodDefault(),
    colorMedium = CONSTANTS.GetColorMediumDefault(),
    colorBad = CONSTANTS.GetColorBadDefault(),
    thresholdMedium = CONSTANTS.DEFAULT_THRESHOLD_GOOD,
    thresholdBad = CONSTANTS.DEFAULT_THRESHOLD_BAD,
    locked = false,
    fontSize = CONSTANTS.DEFAULT_FONT_SIZE,
    showMs = false,
}

-- BUSINESS LOGIC MODULE

local BusinessLogic = {}
BusinessLogic.__index = BusinessLogic

function BusinessLogic.New(settings)
    local self = setmetatable({}, BusinessLogic)
    self.settings = settings
    return self
end

function BusinessLogic:_GetColorForLatency(latency)
    if latency < self.settings.thresholdMedium then
        return self.settings.colorGood
    elseif latency < self.settings.thresholdBad then
        return self.settings.colorMedium
    else
        return self.settings.colorBad
    end
end

function BusinessLogic:GetLatencyColor(latency)
    local color = self:_GetColorForLatency(latency)
    return color.r, color.g, color.b, color.a
end

-- Valid anchor points lookup (hoisted for performance)
local VALID_ANCHOR_POINTS = {
    [TOP] = true, [BOTTOM] = true, [LEFT] = true, [RIGHT] = true,
    [TOPLEFT] = true, [TOPRIGHT] = true, [BOTTOMLEFT] = true, [BOTTOMRIGHT] = true,
    [CENTER] = true,
}

function BusinessLogic:ValidatePosition(point, relativePoint, offsetX, offsetY)
    -- Validate types first
    if type(point) ~= "number" or type(relativePoint) ~= "number" then
        return false
    end

    -- Validate point is a valid anchor constant
    if not VALID_ANCHOR_POINTS[point] or not VALID_ANCHOR_POINTS[relativePoint] then
        return false
    end

    -- Validate offsets are numbers within reasonable bounds
    if type(offsetX) ~= "number" or type(offsetY) ~= "number" then
        return false
    end

    if offsetX < CONSTANTS.MIN_OFFSET or offsetX > CONSTANTS.MAX_OFFSET then
        return false
    end

    if offsetY < CONSTANTS.MIN_OFFSET or offsetY > CONSTANTS.MAX_OFFSET then
        return false
    end

    return true
end

function BusinessLogic:GetPositionFromAnchor(control)
    if not control then return nil end

    local isValid, point, _, relativePoint, offsetX, offsetY = control:GetAnchor(0)
    if not isValid then return nil end

    -- Validate the extracted values
    if not self:ValidatePosition(point, relativePoint, offsetX, offsetY) then
        return nil
    end

    return {
        point = point,
        relativePoint = relativePoint,
        offsetX = offsetX,
        offsetY = offsetY,
    }
end

-- VIEW MODULE

local ViewModule = {}
ViewModule.__index = ViewModule

function ViewModule.New()
    local self = setmetatable({}, ViewModule)
    return self
end

function ViewModule:Create(settings)
    -- Create main control (this throws on failure, never returns nil)
    self.control = CreateTopLevelWindow(ADDON_NAME .. "Display")

    self.control:SetDimensions(CONSTANTS.CONTROL_WIDTH, CONSTANTS.CONTROL_HEIGHT)
    self.control:SetMouseEnabled(true)
    self.control:SetMovable(true)
    self.control:SetHidden(false)

    self.control:SetAnchor(
        settings.posPoint,
        GuiRoot,
        settings.posRelativePoint,
        settings.posOffsetX,
        settings.posOffsetY
    )

    -- Create label
    self.label = CreateControl("$(parent)Label", self.control, CT_LABEL)
    if self.label then
        self.label:SetAnchor(CENTER, self.control, CENTER, 0, 0)
        self.label:SetFont(FONT_STRINGS[settings.fontSize] or FONT_STRINGS[CONSTANTS.DEFAULT_FONT_SIZE])
        self.label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
        self.label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        self.label:SetText("Ping:--")
        self.label:SetMouseEnabled(true)
    end

    -- Set up event handlers
    self:SetupEventHandlers(settings)

    return true
end

function ViewModule:SetupEventHandlers(settings)
    local control = self.control
    local label = self.label

    if not control then return end

    -- Main control handlers
    control:SetHandler("OnMouseDown", function(selfCtrl, button)
        if button == LEFT_MOUSE_BUTTON and not settings.locked then
            if self.onMoveStart then self.onMoveStart() end
            selfCtrl:StartMoving()
        end
    end)

    control:SetHandler("OnMouseUp", function(selfCtrl, button)
        if button == LEFT_MOUSE_BUTTON then
            selfCtrl:StopMovingOrResizing()
            if self.onMoveEnd then self.onMoveEnd() end
        end
    end)

    -- Label handlers (pass through to control)
    local function OnMouseDown(_, button)
        if button == LEFT_MOUSE_BUTTON and not settings.locked then
            if self.onMoveStart then self.onMoveStart() end
            control:StartMoving()
        end
    end

    local function OnMouseUp(_, button)
        if button == LEFT_MOUSE_BUTTON then
            control:StopMovingOrResizing()
            if self.onMoveEnd then self.onMoveEnd() end
        end
    end

    if label then
        label:SetHandler("OnMouseDown", OnMouseDown)
        label:SetHandler("OnMouseUp", OnMouseUp)
    end
end

function ViewModule:Update(latency, formatStr, r, g, b, a)
    if not self.label then return end

    self.label:SetText(string.format(formatStr, latency))
    self.label:SetColor(r, g, b, a)
end

function ViewModule:UpdateUnknown()
    if not self.label then return end

    self.label:SetText("Ping:--")
    self.label:SetColor(0.5, 0.5, 0.5, 1)
end

function ViewModule:ResetPosition(defaults)
    if not self.control then return end

    self.control:ClearAnchors()
    self.control:SetAnchor(
        defaults.posPoint,
        GuiRoot,
        defaults.posRelativePoint,
        defaults.posOffsetX,
        defaults.posOffsetY
    )
end

function ViewModule:ToggleVisibility()
    if not self.control then return end
    self.control:SetHidden(not self.control:IsHidden())
end

function ViewModule:SetOnMoveStart(callback)
    self.onMoveStart = callback
end

function ViewModule:SetOnMoveEnd(callback)
    self.onMoveEnd = callback
end

function ViewModule:SetFontSize(size)
    if self.label and FONT_STRINGS[size] then
        self.label:SetFont(FONT_STRINGS[size])
    end
end

function ViewModule:SetLocked(locked)
    if self.control then
        self.control:SetMouseEnabled(not locked)
        self.control:SetMovable(not locked)
    end
    if self.label then
        self.label:SetMouseEnabled(not locked)
    end
end

-- MAIN ADDON

local addon = {}
_G[ADDON_NAME] = addon

function addon:SavePosition()
    if not self.businessLogic or not self.view or not self.view.control then
        return
    end

    local position = self.businessLogic:GetPositionFromAnchor(self.view.control)
    if not position then
        return
    end

    self.settings.posPoint = position.point
    self.settings.posRelativePoint = position.relativePoint
    self.settings.posOffsetX = position.offsetX
    self.settings.posOffsetY = position.offsetY
end

function addon:SetUpdateInterval(interval)
    self.settings.updateInterval = interval
    EVENT_MANAGER:UnregisterForUpdate(ADDON_NAME .. "_Update")
    EVENT_MANAGER:RegisterForUpdate(ADDON_NAME .. "_Update", interval, function()
        self:UpdatePing()
    end)
end

local FORMAT_WITH_MS = "Ping:%dms"
local FORMAT_WITHOUT_MS = "Ping:%d"

function addon:UpdatePing()
    if not self.view then return end

    local latency = GetLatency()
    if not latency or type(latency) ~= "number" then
        self.view:UpdateUnknown()
        return
    end

    local formatStr = self.settings.showMs and FORMAT_WITH_MS or FORMAT_WITHOUT_MS
    local r, g, b, a = self.businessLogic:GetLatencyColor(latency)
    self.view:Update(latency, formatStr, r, g, b, a)
end

function addon:HandleSlashCommand(args)
    if not self.view then return end

    local command = args and args:lower() or ""

    if command == "reset" then
        self.view:ResetPosition(DEFAULTS)
        self.settings.posPoint = DEFAULTS.posPoint
        self.settings.posRelativePoint = DEFAULTS.posRelativePoint
        self.settings.posOffsetX = DEFAULTS.posOffsetX
        self.settings.posOffsetY = DEFAULTS.posOffsetY
    elseif command == "config" or command == "settings" then
        local LAM = LibAddonMenu2
        if LAM then
            LAM:OpenToPanel(ADDON_NAME .. "_Panel")
        else
            local msg = ADDON_NAME .. ": LibAddonMenu-2.0 is required for the settings panel."
            if CHAT_SYSTEM and CHAT_SYSTEM.primaryContainer then
                CHAT_SYSTEM.primaryContainer.currentBuffer:AddMessage(msg)
            end
        end
    else
        self.view:ToggleVisibility()
    end
end

function addon:CreateSettingsPanel()
    local LAM = LibAddonMenu2
    if not LAM then return end

    local panelData = {
        type = "panel",
        name = ADDON_NAME,
        version = ADDON_VERSION,
        slashCommand = "/simpleping",
        registerForRefresh = true,
        registerForDefaults = true,
    }

    local optionsData = {
        {
            type = "header",
            name = "General Settings",
        },
        {
            type = "slider",
            name = "Update Interval (ms)",
            tooltip = "How often to update the ping display",
            min = CONSTANTS.MIN_UPDATE_INTERVAL_MS,
            max = CONSTANTS.MAX_UPDATE_INTERVAL_MS,
            step = CONSTANTS.UPDATE_INTERVAL_STEP_MS,
            getFunc = function() return self.settings.updateInterval end,
            setFunc = function(value)
                self:SetUpdateInterval(value)
            end,
            default = CONSTANTS.DEFAULT_UPDATE_INTERVAL_MS,
        },
        {
            type = "checkbox",
            name = "Lock Position",
            tooltip = "Prevent the ping display from being moved and block mouse input",
            getFunc = function() return self.settings.locked end,
            setFunc = function(value)
                self.settings.locked = value
                if self.view then
                    self.view:SetLocked(value)
                end
            end,
            default = false,
        },
        {
            type = "checkbox",
            name = "Show 'ms' Suffix",
            tooltip = "Show 'ms' after the ping value",
            getFunc = function() return self.settings.showMs end,
            setFunc = function(value)
                self.settings.showMs = value
                self:UpdatePing()
            end,
            default = false,
        },
        {
            type = "slider",
            name = "Font Size",
            tooltip = "Size of the ping display text",
            min = CONSTANTS.MIN_FONT_SIZE,
            max = CONSTANTS.MAX_FONT_SIZE,
            step = CONSTANTS.FONT_SIZE_STEP,
            getFunc = function() return self.settings.fontSize end,
            setFunc = function(value)
                self.settings.fontSize = value
                if self.view then
                    self.view:SetFontSize(value)
                end
                self:UpdatePing()
            end,
            default = CONSTANTS.DEFAULT_FONT_SIZE,
        },
        {
            type = "header",
            name = "Color Settings",
        },
        {
            type = "colorpicker",
            name = "Good Ping Color",
            tooltip = "Color when ping is below threshold",
            getFunc = function() return self.settings.colorGood.r, self.settings.colorGood.g, self.settings.colorGood.b, self.settings.colorGood.a end,
            setFunc = function(r, g, b, a)
                self.settings.colorGood = { r = r, g = g, b = b, a = a }
                self:UpdatePing()
            end,
            default = CONSTANTS.GetColorGoodDefault(),
        },
        {
            type = "slider",
            name = "Good Threshold (ms)",
            tooltip = "Ping below this is considered 'good'",
            min = CONSTANTS.MIN_THRESHOLD,
            max = CONSTANTS.MAX_THRESHOLD_GOOD,
            step = CONSTANTS.THRESHOLD_STEP,
            getFunc = function() return self.settings.thresholdMedium end,
            setFunc = function(value)
                self.settings.thresholdMedium = value
                -- Ensure medium threshold stays below bad threshold
                if self.settings.thresholdMedium >= self.settings.thresholdBad then
                    self.settings.thresholdBad = math.min(self.settings.thresholdMedium + CONSTANTS.THRESHOLD_STEP, CONSTANTS.MAX_THRESHOLD_BAD)
                end
            end,
            default = CONSTANTS.DEFAULT_THRESHOLD_GOOD,
        },
        {
            type = "colorpicker",
            name = "Medium Ping Color",
            tooltip = "Color when ping is between thresholds",
            getFunc = function() return self.settings.colorMedium.r, self.settings.colorMedium.g, self.settings.colorMedium.b, self.settings.colorMedium.a end,
            setFunc = function(r, g, b, a)
                self.settings.colorMedium = { r = r, g = g, b = b, a = a }
                self:UpdatePing()
            end,
            default = CONSTANTS.GetColorMediumDefault(),
        },
        {
            type = "slider",
            name = "Bad Threshold (ms)",
            tooltip = "Ping above this is considered 'bad'",
            min = CONSTANTS.MIN_THRESHOLD,
            max = CONSTANTS.MAX_THRESHOLD_BAD,
            step = CONSTANTS.THRESHOLD_STEP,
            getFunc = function() return self.settings.thresholdBad end,
            setFunc = function(value)
                self.settings.thresholdBad = value
                -- Ensure bad threshold stays above medium threshold
                if self.settings.thresholdBad <= self.settings.thresholdMedium then
                    self.settings.thresholdMedium = math.max(self.settings.thresholdBad - CONSTANTS.THRESHOLD_STEP, CONSTANTS.MIN_THRESHOLD)
                end
            end,
            default = CONSTANTS.DEFAULT_THRESHOLD_BAD,
        },
        {
            type = "colorpicker",
            name = "Bad Ping Color",
            tooltip = "Color when ping is above threshold",
            getFunc = function() return self.settings.colorBad.r, self.settings.colorBad.g, self.settings.colorBad.b, self.settings.colorBad.a end,
            setFunc = function(r, g, b, a)
                self.settings.colorBad = { r = r, g = g, b = b, a = a }
                self:UpdatePing()
            end,
            default = CONSTANTS.GetColorBadDefault(),
        },
        {
            type = "header",
            name = "Commands",
        },
        {
            type = "description",
            text = "/simpleping - Toggle visibility\n/simpleping reset - Reset position to top center\n/simpleping config - Open settings",
        },
    }

    LAM:RegisterAddonPanel(ADDON_NAME .. "_Panel", panelData)
    LAM:RegisterOptionControls(ADDON_NAME .. "_Panel", optionsData)
end

local function OnAddonLoaded(eventCode, addonName)
    if addonName ~= ADDON_NAME then return end

    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)

    -- Load saved variables
    addon.settings = ZO_SavedVars:NewAccountWide(ADDON_NAME .. "SavedVars", SAVED_VARS_VERSION, nil, DEFAULTS)

    -- Initialize business logic
    addon.businessLogic = BusinessLogic.New(addon.settings)

    -- Validate saved position, reset to defaults if invalid
    if not addon.businessLogic:ValidatePosition(
        addon.settings.posPoint,
        addon.settings.posRelativePoint,
        addon.settings.posOffsetX,
        addon.settings.posOffsetY
    ) then
        addon.settings.posPoint = DEFAULTS.posPoint
        addon.settings.posRelativePoint = DEFAULTS.posRelativePoint
        addon.settings.posOffsetX = DEFAULTS.posOffsetX
        addon.settings.posOffsetY = DEFAULTS.posOffsetY
    end

    -- Initialize and create view
    addon.view = ViewModule.New()
    addon.view:SetOnMoveEnd(function()
        addon:SavePosition()
    end)

    local success = addon.view:Create(addon.settings)
    if not success then
        return
    end

    -- Apply initial locked state
    addon.view:SetLocked(addon.settings.locked)

    -- Register for periodic updates
    EVENT_MANAGER:RegisterForUpdate(ADDON_NAME .. "_Update", addon.settings.updateInterval, function() addon:UpdatePing() end)

    -- Create settings panel
    addon:CreateSettingsPanel()

    -- Register slash command
    SLASH_COMMANDS["/simpleping"] = function(args)
        addon:HandleSlashCommand(args)
    end

    -- Do initial update
    addon:UpdatePing()

    -- Save position on logout/reload (backup in case mouse-up never fired)
    EVENT_MANAGER:RegisterForEvent(ADDON_NAME .. "_Save", EVENT_PLAYER_DEACTIVATED, function()
        addon:SavePosition()
    end)
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddonLoaded)
