local helpers = ...
local WidgetFns = public.widgets

---@class InputTextOpts
---@field label string|nil
---@field tooltip string|nil
---@field maxLen number|nil
---@field labelWidth number|nil
---@field controlWidth number|nil
---@field controlGap number|nil

---@param imgui table
---@param session Session
---@param alias string
---@param opts InputTextOpts|nil
---@return boolean
function WidgetFns.inputText(imgui, session, alias, opts)
    opts = opts or {}
    local current = tostring(session.read(alias) or "")
    local maxLen = math.max(math.floor(tonumber(opts.maxLen) or 256), 1)
    local controlWidth = tonumber(opts.controlWidth) or 120

    helpers.DrawInlineLabel(imgui, opts.label, opts.tooltip, opts.controlGap, opts.labelWidth)

    if controlWidth > 0 then
        imgui.PushItemWidth(controlWidth)
    end
    local nextValue, changed = imgui.InputText("##" .. tostring(alias), current, maxLen)
    if controlWidth > 0 then
        imgui.PopItemWidth()
    end
    helpers.ShowTooltip(imgui, opts.tooltip)
    if changed then
        session.write(alias, nextValue)
        return true
    end
    return false
end
