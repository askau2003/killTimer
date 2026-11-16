local ns = killTimerNS
local f = ns.frame
local ApplySize = ns.ApplySize
local ShowCopyPopup = ns.ShowCopyPopup

-- Options panel, shown under Settings > AddOns > killTimer.
local options = CreateFrame("Frame", "killTimerOptionsPanel", UIParent)
options.name = "killTimer"

local optTitle = options:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
optTitle:SetPoint("TOPLEFT", 16, -16)
optTitle:SetText("killTimer")

-- Guards the widget OnValueChanged/OnClick handlers below while SyncControls()
-- re-applies killTimerDB to them, so that resync doesn't loop back and rewrite
-- the very values it's reading. Needed because sliders are created (and get
-- their first SetValue) while this panel is still hidden - their thumb doesn't
-- render at the right spot until the panel is actually shown and laid out, so
-- every OnShow re-syncs the widgets to the saved values instead of whatever
-- they happened to visually settle on.
local syncing = false

local scaleSlider = CreateFrame("Slider", "killTimerOptionsScale", options, "OptionsSliderTemplate")
scaleSlider:SetPoint("TOPLEFT", optTitle, "BOTTOMLEFT", 8, -32)
scaleSlider:SetWidth(200)
scaleSlider:SetMinMaxValues(0.5, 2)
scaleSlider:SetValueStep(0.05)
scaleSlider:SetObeyStepOnDrag(true)
scaleSlider.Low:SetText("0.5")
scaleSlider.High:SetText("2.0")
local function UpdateScaleLabel(value)
    scaleSlider.Text:SetText(("Scale (%.2f)"):format(value))
end
scaleSlider:SetScript("OnValueChanged", function(_, value)
    if syncing then return end
    value = math.floor(value * 20 + 0.5) / 20
    killTimerDB.scale = value
    f:SetScale(value)
    UpdateScaleLabel(value)
end)

local widthSlider = CreateFrame("Slider", "killTimerOptionsWidth", options, "OptionsSliderTemplate")
widthSlider:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -32)
widthSlider:SetWidth(200)
widthSlider:SetMinMaxValues(ns.WIDTH_MIN, ns.WIDTH_MAX)
widthSlider:SetValueStep(10)
widthSlider:SetObeyStepOnDrag(true)
widthSlider.Low:SetText(tostring(ns.WIDTH_MIN))
widthSlider.High:SetText(tostring(ns.WIDTH_MAX))
local function UpdateWidthLabel(value)
    widthSlider.Text:SetText(("Width (%d)"):format(value))
end
widthSlider:SetScript("OnValueChanged", function(_, value)
    if syncing then return end
    value = math.floor(value + 0.5)
    killTimerDB.width = value
    ApplySize(value, killTimerDB.height)
    UpdateWidthLabel(value)
end)

local heightSlider = CreateFrame("Slider", "killTimerOptionsHeight", options, "OptionsSliderTemplate")
heightSlider:SetPoint("TOPLEFT", widthSlider, "BOTTOMLEFT", 0, -32)
heightSlider:SetWidth(200)
heightSlider:SetMinMaxValues(ns.HEIGHT_MIN, ns.HEIGHT_MAX)
heightSlider:SetValueStep(10)
heightSlider:SetObeyStepOnDrag(true)
heightSlider.Low:SetText(tostring(ns.HEIGHT_MIN))
heightSlider.High:SetText(tostring(ns.HEIGHT_MAX))
local function UpdateHeightLabel(value)
    heightSlider.Text:SetText(("Height (%d)"):format(value))
end
heightSlider:SetScript("OnValueChanged", function(_, value)
    if syncing then return end
    value = math.floor(value + 0.5)
    killTimerDB.height = value
    ApplySize(killTimerDB.width, value)
    UpdateHeightLabel(value)
end)

local lockCheck = CreateFrame("CheckButton", "killTimerOptionsLock", options, "UICheckButtonTemplate")
lockCheck:SetPoint("TOPLEFT", heightSlider, "BOTTOMLEFT", -8, -28)
lockCheck.Text:SetText("Lock position")
lockCheck:SetScript("OnClick", function(self)
    if syncing then return end
    killTimerDB.locked = self:GetChecked() and true or false
end)

local resetButton = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
resetButton:SetSize(140, 22)
resetButton:SetPoint("TOPLEFT", lockCheck, "BOTTOMLEFT", 8, -20)
resetButton:SetText("Reset position")
resetButton:SetScript("OnClick", function()
    killTimerDB.point = nil
    f:ClearAllPoints()
    f:SetPoint(unpack(ns.DEFAULT_POINT))
end)

local copyButton = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
copyButton:SetSize(140, 22)
copyButton:SetPoint("TOPLEFT", resetButton, "BOTTOMLEFT", 0, -12)
copyButton:SetText("Copy data to share")
copyButton:SetScript("OnClick", ShowCopyPopup)

local function SyncControls()
    syncing = true
    scaleSlider:SetValue(killTimerDB.scale)
    UpdateScaleLabel(killTimerDB.scale)
    widthSlider:SetValue(killTimerDB.width)
    UpdateWidthLabel(killTimerDB.width)
    heightSlider:SetValue(killTimerDB.height)
    UpdateHeightLabel(killTimerDB.height)
    lockCheck:SetChecked(killTimerDB.locked)
    syncing = false
end
SyncControls()
options:SetScript("OnShow", SyncControls)

if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(options, options.name)
    Settings.RegisterAddOnCategory(category)
else
    InterfaceOptions_AddCategory(options)
end
