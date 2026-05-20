local helpers = ...

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
function helpers.widgets.inputText(imgui, session, alias, opts)
    opts = opts or {}
    local field = helpers.ResolveStorageField(session, alias, "widgets.inputText")
    local fieldAlias = field:alias()
    local current = tostring(field:read() or "")
    local maxLen = math.max(math.floor(tonumber(opts.maxLen) or 256), 1)
    local label = tostring(opts.label or "")
    local controlWidth = tonumber(opts.controlWidth) or 120

    if label ~= "" then
        helpers.DrawInlineLabel(imgui, label, opts.tooltip, opts.labelWidth, opts.controlGap)
    end

    if controlWidth > 0 then
        imgui.PushItemWidth(controlWidth)
    end
    local nextValue, changed = imgui.InputText("##" .. tostring(fieldAlias), current, maxLen)
    if controlWidth > 0 then
        imgui.PopItemWidth()
    end
    helpers.ShowTooltip(imgui, opts.tooltip)
    if changed then
        field:write(nextValue)
        return true
    end
    return false
end
