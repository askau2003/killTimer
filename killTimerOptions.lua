local ns = killTimerNS
local f = ns.frame
local ApplySize = ns.ApplySize

-- Options panel, shown under Settings > AddOns > killTimer.
local options = CreateFrame("Frame", "killTimerOptionsPanel", UIParent)
options.name = "killTimer"

local optTitle = options:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
optTitle:SetPoint("TOPLEFT", 16, -16)
optTitle:SetText("killTimer")

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
    value = math.floor(value * 20 + 0.5) / 20
    killTimerDB.scale = value
    f:SetScale(value)
    UpdateScaleLabel(value)
end)
scaleSlider:SetValue(killTimerDB.scale)
UpdateScaleLabel(killTimerDB.scale)

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
    value = math.floor(value + 0.5)
    killTimerDB.width = value
    ApplySize(value, killTimerDB.height)
    UpdateWidthLabel(value)
end)
widthSlider:SetValue(killTimerDB.width)
UpdateWidthLabel(killTimerDB.width)

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
    value = math.floor(value + 0.5)
    killTimerDB.height = value
    ApplySize(killTimerDB.width, value)
    UpdateHeightLabel(value)
end)
heightSlider:SetValue(killTimerDB.height)
UpdateHeightLabel(killTimerDB.height)

local lockCheck = CreateFrame("CheckButton", "killTimerOptionsLock", options, "UICheckButtonTemplate")
lockCheck:SetPoint("TOPLEFT", heightSlider, "BOTTOMLEFT", -8, -28)
lockCheck.Text:SetText("Lock position")
lockCheck:SetChecked(killTimerDB.locked)
lockCheck:SetScript("OnClick", function(self)
    killTimerDB.locked = self:GetChecked() and true or false
end)

local resetButton = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
resetButton:SetSize(140, 22)
resetButton:SetPoint("TOPLEFT", lockCheck, "BOTTOMLEFT", 8, -20)
resetButton:SetText("Reset position")
resetButton:SetScript("OnClick", function()
    f:ClearAllPoints()
    f:SetPoint(unpack(ns.DEFAULT_POINT))
end)

if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(options, options.name)
    Settings.RegisterAddOnCategory(category)
else
    InterfaceOptions_AddCategory(options)
end
