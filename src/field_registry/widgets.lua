local internal = AdamantModpackLib_Internal
local shared = internal.shared
local StorageTypes = shared.StorageTypes
local WidgetTypes = shared.WidgetTypes
local libWarn = shared.libWarn
local registry = shared.fieldRegistry

local NormalizeInteger = registry.NormalizeInteger
local NormalizeChoiceValue = registry.NormalizeChoiceValue
local NormalizeColor = registry.NormalizeColor
local PrepareWidgetText = registry.PrepareWidgetText
local ChoiceDisplay = registry.ChoiceDisplay
local GetCursorPosXSafe = registry.GetCursorPosXSafe
local SetCursorPosSafe = registry.SetCursorPosSafe
local GetStyleMetricX = registry.GetStyleMetricX
local CalcTextWidth = registry.CalcTextWidth
local EstimateButtonWidth = registry.EstimateButtonWidth
local EstimateStructuredRowAdvanceY = registry.EstimateStructuredRowAdvanceY
local DrawStructuredAt = registry.DrawStructuredAt
local GetSlotGeometry = registry.GetSlotGeometry
local ShowPreparedTooltip = registry.ShowPreparedTooltip

local DEFAULT_PACKED_SLOT_COUNT = 32

local function BuildIndexedSlots(count, buildSlot)
    local slots = {}
    for index = 1, count do
        slots[index] = buildSlot(index)
    end
    return slots
end

local function WarnIgnoredSlotKeys(prefix, geometry, slotName, keys, widgetTypeName)
    local slot = type(geometry) == "table" and geometry[slotName] or nil
    if type(slot) ~= "table" then
        return
    end
    for _, key in ipairs(keys) do
        if slot[key] ~= nil then
            libWarn("%s: geometry slot '%s' %s is ignored by widget type '%s'",
                prefix, tostring(slotName), tostring(key), tostring(widgetTypeName))
        end
    end
end

local function WarnIgnoredDynamicSlotKeys(prefix, geometry, pattern, keys, widgetTypeName)
    if type(geometry) ~= "table" then
        return
    end
    for slotName, slot in pairs(geometry) do
        if type(slotName) == "string" and string.match(slotName, pattern) and type(slot) == "table" then
            for _, key in ipairs(keys) do
                if slot[key] ~= nil then
                    libWarn("%s: geometry slot '%s' %s is ignored by widget type '%s'",
                        prefix, tostring(slotName), tostring(key), tostring(widgetTypeName))
                end
            end
        end
    end
end

local function ValidateValueColorsTable(node, prefix, widgetName)
    node._valueColors = nil
    if node.valueColors == nil then
        return
    end
    if type(node.valueColors) ~= "table" then
        libWarn("%s: %s valueColors must be a table", prefix, widgetName)
        return
    end

    local normalizedColors = {}
    for key, color in pairs(node.valueColors) do
        local normalized = NormalizeColor(color)
        if normalized == nil then
            libWarn("%s: %s valueColors[%s] must be a 3- or 4-number color table", prefix, widgetName, tostring(key))
        else
            normalizedColors[key] = normalized
        end
    end
    node._valueColors = normalizedColors
end

local function DrawWithValueColor(imgui, color, drawFn)
    if type(color) ~= "table" or type(imgui.PushStyleColor) ~= "function" or type(imgui.PopStyleColor) ~= "function" then
        return drawFn()
    end

    local textEnum = imgui.ImGuiCol and imgui.ImGuiCol.Text or 0
    imgui.PushStyleColor(textEnum, color[1], color[2], color[3], color[4])
    local ok, a, b, c, d = pcall(drawFn)
    imgui.PopStyleColor()
    if not ok then
        error(a)
    end
    return a, b, c, d
end

local function EstimateToggleWidth(imgui, label)
    local frameHeight = type(imgui.GetFrameHeight) == "function" and imgui.GetFrameHeight() or nil
    if type(frameHeight) ~= "number" or frameHeight <= 0 then
        frameHeight = EstimateStructuredRowAdvanceY(imgui)
    end
    local style = type(imgui.GetStyle) == "function" and imgui.GetStyle() or nil
    local itemInnerSpacingX = GetStyleMetricX(style, "ItemInnerSpacing", 4)
    return frameHeight + itemInnerSpacingX + CalcTextWidth(imgui, label)
end

local function ResolveSingleSlotPlacement(node, slotName, startX, contentWidth)
    local geometry = type(slotName) == "string" and GetSlotGeometry(node, slotName) or nil
    local slotX = type(geometry) == "table" and type(geometry.start) == "number"
        and (startX + geometry.start)
        or startX
    local drawX = slotX
    local slotWidth = type(geometry) == "table" and geometry.width or nil
    local align = type(geometry) == "table" and geometry.align or nil

    if type(slotWidth) == "number" and type(contentWidth) == "number" then
        local offset = 0
        if align == "center" then
            offset = math.max((slotWidth - contentWidth) / 2, 0)
        elseif align == "right" then
            offset = math.max(slotWidth - contentWidth, 0)
        end
        drawX = slotX + offset
    end

    return slotX, drawX, slotWidth
end

local function MakeSelectableId(label, uniqueId)
    return tostring(label or "") .. "##" .. tostring(uniqueId or "")
end

local function ValidateDisplayValuesTable(node, prefix, widgetName)
    if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
        libWarn("%s: %s displayValues must be a table", prefix, widgetName)
    end
end

local function GetPackedChoiceMode(node)
    local mode = node.selectionMode
    if mode == nil or mode == "" then
        return "singleEnabled"
    end
    return mode
end

local function GetPackedChoiceChildren(node, bound, widgetName)
    local children = bound and bound.value and bound.value.children or nil
    if type(children) ~= "table" then
        libWarn("%s: no packed children for alias '%s'; bind to a packedInt root",
            widgetName, tostring(node.binds and node.binds.value))
        return nil
    end
    return children
end

local function GetPackedChoiceLabel(node, child)
    if type(node.displayValues) == "table" and node.displayValues[child.alias] ~= nil then
        return tostring(node.displayValues[child.alias])
    end
    return tostring(child.label or child.alias or "")
end

local function GetPackedChoiceNoneValue(mode)
    if mode == "singleRemaining" then
        return false
    end
    return false
end

local function IsPackedChoiceActive(mode, value)
    if mode == "singleRemaining" then
        return value == false
    end
    return value == true
end

local function GetPackedChoiceWriteValue(mode, isActive)
    if mode == "singleRemaining" then
        if isActive then
            return false
        end
        return true
    end
    return isActive == true
end

local function ClassifyPackedChoice(node, children)
    local mode = GetPackedChoiceMode(node)
    local noneValue = GetPackedChoiceNoneValue(mode)
    local activeCount = 0
    local totalCount = 0
    local lastActiveChild = nil

    for _, child in ipairs(children or {}) do
        totalCount = totalCount + 1
        local value = child.get and child.get() or noneValue
        if value == nil then
            value = noneValue
        end
        if IsPackedChoiceActive(mode, value) then
            activeCount = activeCount + 1
            lastActiveChild = child
        end
    end

    local state = "multiple"
    if activeCount == 0 then
        state = "none"
    elseif activeCount == 1 then
        state = "single"
    elseif mode == "singleRemaining" and activeCount == totalCount then
        state = "none"
    end

    return {
        state = state,
        selectedChild = state == "single" and lastActiveChild or nil,
        mode = mode,
        noneValue = noneValue,
    }
end

local function ApplyPackedChoiceSelection(children, selectedAlias, selection)
    local changed = false
    for _, child in ipairs(children or {}) do
        local shouldBeActive = child.alias == selectedAlias
        local nextValue = GetPackedChoiceWriteValue(selection.mode, shouldBeActive)
        local currentValue = child.get and child.get() or selection.noneValue
        if currentValue == nil then
            currentValue = selection.noneValue
        end
        if currentValue ~= nextValue then
            child.set(nextValue)
            changed = true
        end
    end
    return changed
end

local function ClearPackedChoiceSelection(children, selection)
    local changed = false
    for _, child in ipairs(children or {}) do
        local currentValue = child.get and child.get() or selection.noneValue
        if currentValue == nil then
            currentValue = selection.noneValue
        end
        if currentValue ~= selection.noneValue then
            child.set(selection.noneValue)
            changed = true
        end
    end
    return changed
end

local function ValidatePackedChoiceWidget(node, prefix, widgetName)
    local mode = GetPackedChoiceMode(node)
    if mode ~= "singleEnabled" and mode ~= "singleRemaining" then
        libWarn("%s: %s selectionMode must be 'singleEnabled' or 'singleRemaining'", prefix, widgetName)
    end
    if node.noneLabel ~= nil and type(node.noneLabel) ~= "string" then
        libWarn("%s: %s noneLabel must be a string", prefix, widgetName)
    end
    if node.multipleLabel ~= nil and type(node.multipleLabel) ~= "string" then
        libWarn("%s: %s multipleLabel must be a string", prefix, widgetName)
    end
    ValidateDisplayValuesTable(node, prefix, widgetName)
    ValidateValueColorsTable(node, prefix, widgetName)
end

local function PrepareStepperDrawContext(node, boundValue, limits)
    local ctx = node._stepperCtx or {}
    ctx.boundValue = boundValue
    ctx.renderedValue = NormalizeInteger(node, boundValue:get())
    ctx.min = limits and limits.min or node.min
    ctx.max = limits and limits.max or node.max
    ctx.valueSlotStart = nil
    ctx.valueSlotWidth = nil
    node._stepperCtx = ctx
end

local function BuildOrderedStepperEntries(node, options)
    options = options or {}
    local label = node._label or ""
    local hasLabel = options.drawLabel ~= false and label ~= ""
    local slotPrefix = options.slotPrefix or ""
    local labelSlotName = options.labelSlotName or "label"
    local firstSlotSameLine = options.firstSlotSameLine == true or hasLabel
    local geometryOwner = options.geometryOwner or node
    local entries = {}

    local function SlotName(name)
        return slotPrefix ~= "" and (slotPrefix .. name) or name
    end

    local function GeometryFor(name)
        return GetSlotGeometry(geometryOwner, name)
    end

    local function AddEntry(name, config)
        local geometry = GeometryFor(name)
        entries[#entries + 1] = {
            index = #entries + 1,
            name = name,
            line = (geometry and geometry.line) or config.line or 1,
            start = (geometry and geometry.start) or config.start,
            width = (geometry and geometry.width) or config.width,
            align = (geometry and geometry.align) or config.align,
            sameLine = config.sameLine,
            estimateWidth = config.estimateWidth,
            render = config.render,
        }
    end

    local function GetStepperLimits()
        local ctx = node._stepperCtx
        local minValue = ctx and ctx.min ~= nil and ctx.min or node.min
        local maxValue = ctx and ctx.max ~= nil and ctx.max or node.max
        return minValue, maxValue
    end

    local function CommitValue(nextValue)
        local ctx = node._stepperCtx
        if not ctx or not ctx.boundValue then
            return false
        end
        local minValue, maxValue = GetStepperLimits()
        local normalized = NormalizeInteger(node, nextValue)
        if minValue ~= nil and normalized < minValue then
            normalized = minValue
        end
        if maxValue ~= nil and normalized > maxValue then
            normalized = maxValue
        end
        if normalized ~= ctx.renderedValue then
            ctx.renderedValue = normalized
            ctx.boundValue:set(normalized)
            return true
        end
        return false
    end

    local function GetValueText()
        local ctx = node._stepperCtx
        local renderedValue = ctx and ctx.renderedValue or NormalizeInteger(node, node.default)
        if ctx._lastStepperVal ~= renderedValue or ctx._lastStepperStr == nil then
            local displayValue = node.displayValues and node.displayValues[renderedValue]
            ctx._lastStepperStr = tostring(displayValue ~= nil and displayValue or renderedValue)
            ctx._lastStepperVal = renderedValue
        end
        return ctx._lastStepperStr, renderedValue
    end

    if hasLabel then
        AddEntry(labelSlotName, {
            estimateWidth = function(imgui)
                return CalcTextWidth(imgui, label)
            end,
            render = function(imgui)
                imgui.Text(label)
                ShowPreparedTooltip(imgui, node)
                return false, CalcTextWidth(imgui, label), EstimateStructuredRowAdvanceY(imgui)
            end,
        })
    end

    AddEntry(SlotName("decrement"), {
        sameLine = firstSlotSameLine,
        estimateWidth = function(imgui)
            return EstimateButtonWidth(imgui, "-")
        end,
        render = function(imgui)
            local ctx = node._stepperCtx
            local renderedValue = ctx and ctx.renderedValue or NormalizeInteger(node, node.default)
            local minValue = GetStepperLimits()
            local changed = imgui.Button("-") and renderedValue > minValue and CommitValue(renderedValue - (node._step or 1)) or false
            return changed, EstimateButtonWidth(imgui, "-"), EstimateStructuredRowAdvanceY(imgui)
        end,
    })

    AddEntry(SlotName("value"), {
        sameLine = true,
        estimateWidth = function(imgui)
            local valueText = GetValueText()
            return CalcTextWidth(imgui, valueText)
        end,
        render = function(imgui, entry)
            local valueText, renderedValue = GetValueText()
            local textWidth = CalcTextWidth(imgui, valueText)
            local color = node._valueColors and node._valueColors[renderedValue] or nil
            local ctx = node._stepperCtx or {}
            ctx.valueSlotWidth = entry.width
            node._stepperCtx = ctx
            if type(color) == "table" then
                imgui.TextColored(color[1], color[2], color[3], color[4], valueText)
            else
                imgui.Text(valueText)
            end
            return false, entry.width or textWidth, EstimateStructuredRowAdvanceY(imgui)
        end,
    })

    AddEntry(SlotName("increment"), {
        sameLine = true,
        estimateWidth = function(imgui)
            return EstimateButtonWidth(imgui, "+")
        end,
        render = function(imgui)
            local ctx = node._stepperCtx
            local renderedValue = ctx and ctx.renderedValue or NormalizeInteger(node, node.default)
            local _, maxValue = GetStepperLimits()
            local changed = imgui.Button("+") and renderedValue < maxValue and CommitValue(renderedValue + (node._step or 1)) or false
            return changed, EstimateButtonWidth(imgui, "+"), EstimateStructuredRowAdvanceY(imgui)
        end,
    })

    if node._fastStep then
        AddEntry(SlotName("fastDecrement"), {
            sameLine = true,
            estimateWidth = function(imgui)
                return EstimateButtonWidth(imgui, "<<")
            end,
            render = function(imgui)
                local ctx = node._stepperCtx
                local renderedValue = ctx and ctx.renderedValue or NormalizeInteger(node, node.default)
                local minValue = GetStepperLimits()
                local changed = imgui.Button("<<")
                    and renderedValue > minValue
                    and CommitValue(renderedValue - node._fastStep)
                    or false
                return changed, EstimateButtonWidth(imgui, "<<"), EstimateStructuredRowAdvanceY(imgui)
            end,
        })
        AddEntry(SlotName("fastIncrement"), {
            sameLine = true,
            estimateWidth = function(imgui)
                return EstimateButtonWidth(imgui, ">>")
            end,
            render = function(imgui)
                local ctx = node._stepperCtx
                local renderedValue = ctx and ctx.renderedValue or NormalizeInteger(node, node.default)
                local _, maxValue = GetStepperLimits()
                local changed = imgui.Button(">>")
                    and renderedValue < maxValue
                    and CommitValue(renderedValue + node._fastStep)
                    or false
                return changed, EstimateButtonWidth(imgui, ">>"), EstimateStructuredRowAdvanceY(imgui)
            end,
        })
    end

    table.sort(entries, function(left, right)
        if left.line ~= right.line then
            return left.line < right.line
        end
        if type(left.start) == "number" and type(right.start) == "number" and left.start ~= right.start then
            return left.start < right.start
        end
        return left.index < right.index
    end)

    return entries
end

local function DrawOrderedEntries(imgui, entries, startX, startY, fallbackHeight)
    local currentLine = nil
    local currentRowY = startY
    local currentRowAdvance = fallbackHeight
    local maxRight = startX
    local maxBottom = startY
    local changed = false

    for _, entry in ipairs(entries or {}) do
        local isNewLine = currentLine ~= entry.line
        if isNewLine then
            if currentLine ~= nil then
                currentRowY = currentRowY + currentRowAdvance
            end
            currentLine = entry.line
            currentRowAdvance = fallbackHeight
        elseif entry.sameLine ~= false and type(entry.start) ~= "number" then
            imgui.SameLine()
        end

        local slotX
        if type(entry.start) == "number" then
            slotX = startX + entry.start
        elseif isNewLine then
            slotX = startX
        else
            slotX = GetCursorPosXSafe(imgui)
        end

        local estimatedWidth = type(entry.estimateWidth) == "function"
            and entry.estimateWidth(imgui, entry)
            or 0
        local drawX = slotX
        if type(entry.width) == "number" and type(estimatedWidth) == "number" then
            local offset = 0
            if entry.align == "center" then
                offset = math.max((entry.width - estimatedWidth) / 2, 0)
            elseif entry.align == "right" then
                offset = math.max(entry.width - estimatedWidth, 0)
            end
            drawX = slotX + offset
        end

        local measuredWidth = estimatedWidth
        local measuredHeight = fallbackHeight
        local entryChanged, _, _, consumedHeight = DrawStructuredAt(
            imgui,
            slotX,
            currentRowY,
            fallbackHeight,
            function()
                if drawX ~= slotX then
                    if type(imgui.SetCursorPosX) == "function" then
                        imgui.SetCursorPosX(drawX)
                    else
                        SetCursorPosSafe(imgui, drawX, currentRowY)
                    end
                end
                local widgetChanged, contentWidth, contentHeight = entry.render(imgui, entry)
                if type(contentWidth) == "number" and contentWidth > 0 then
                    measuredWidth = contentWidth
                end
                if type(contentHeight) == "number" and contentHeight > 0 then
                    measuredHeight = contentHeight
                end
                return widgetChanged == true
            end)
        if entryChanged then
            changed = true
        end

        local slotConsumedHeight = measuredHeight > 0 and measuredHeight or consumedHeight
        if slotConsumedHeight > currentRowAdvance then
            currentRowAdvance = slotConsumedHeight
        end

        local slotConsumedWidth = type(entry.width) == "number" and entry.width or measuredWidth or 0
        local slotRight = slotX + math.max(slotConsumedWidth, 0)
        if slotRight > maxRight then
            maxRight = slotRight
        end
        local slotBottom = currentRowY + math.max(slotConsumedHeight or 0, 0)
        if slotBottom > maxBottom then
            maxBottom = slotBottom
        end
    end

    return math.max(maxRight - startX, 0), math.max(maxBottom - startY, 0), changed
end

WidgetTypes.checkbox = {
    binds = { value = { storageType = "bool" } },
    slots = { "control" },
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "boolean" then
            libWarn("%s: checkbox default must be boolean, got %s", prefix, type(node.default))
        end
        PrepareWidgetText(node, node.binds and node.binds.value)
    end,
    draw = function(imgui, node, bound, x, y)
        node._checkboxBound = bound.value
        node._checkboxValue = bound.value:get()
        if node._checkboxValue == nil then node._checkboxValue = node.default == true end
        local contentWidth = EstimateToggleWidth(imgui, node._label or "")
        local slotX, drawX, slotWidth = ResolveSingleSlotPlacement(node, "control", x, contentWidth)
        local changed, _, _, consumedHeight = DrawStructuredAt(
            imgui,
            slotX,
            y,
            EstimateStructuredRowAdvanceY(imgui),
            function()
                if drawX ~= slotX then
                    if type(imgui.SetCursorPosX) == "function" then
                        imgui.SetCursorPosX(drawX)
                    else
                        SetCursorPosSafe(imgui, drawX, y)
                    end
                end
                local value = node._checkboxValue == true
                local newVal, widgetChanged = imgui.Checkbox((node._label or "") .. (node._imguiId or ""), value)
                ShowPreparedTooltip(imgui, node)
                if widgetChanged then
                    node._checkboxBound:set(newVal)
                    return true
                end
                return false
            end)
        local consumedWidth = type(slotWidth) == "number" and slotWidth or math.max(contentWidth, (drawX - slotX) + contentWidth)
        return consumedWidth, consumedHeight, changed
    end,
}

WidgetTypes.text = {
    binds = { value = { storageType = "string", optional = true } },
    slots = { "value" },
    validate = function(node, prefix)
        if node.text ~= nil and type(node.text) ~= "string" then
            libWarn("%s: text text must be string", prefix)
        end
        if node.label ~= nil and type(node.label) ~= "string" then
            libWarn("%s: text label must be string", prefix)
        end
        if node.color ~= nil then
            if type(node.color) ~= "table" then
                libWarn("%s: text color must be a table", prefix)
            else
                local count = 0
                for i = 1, 4 do
                    if node.color[i] ~= nil then
                        count = count + 1
                        if type(node.color[i]) ~= "number" then
                            libWarn("%s: text color[%d] must be a number", prefix, i)
                        end
                    end
                end
                if count ~= 3 and count ~= 4 then
                    libWarn("%s: text color must have 3 or 4 numeric entries", prefix)
                end
            end
        end
        node._text = tostring(node.text or node.label or "")
        node._color = NormalizeColor(node.color)
        PrepareWidgetText(node)
    end,
    draw = function(imgui, node, bound, x, y)
        node._boundText = bound.value and bound.value:get() or nil
        local text = node._boundText ~= nil and tostring(node._boundText) or node._text or ""
        local contentWidth = CalcTextWidth(imgui, text)
        local slotX, drawX, slotWidth = ResolveSingleSlotPlacement(node, "value", x, contentWidth)
        local color = node._color
        local changed, _, _, consumedHeight = DrawStructuredAt(
            imgui,
            slotX,
            y,
            EstimateStructuredRowAdvanceY(imgui),
            function()
                if drawX ~= slotX then
                    if type(imgui.SetCursorPosX) == "function" then
                        imgui.SetCursorPosX(drawX)
                    else
                        SetCursorPosSafe(imgui, drawX, y)
                    end
                end
                if type(color) == "table" then
                    imgui.TextColored(color[1], color[2], color[3], color[4], text)
                else
                    imgui.Text(text)
                end
                ShowPreparedTooltip(imgui, node)
                return false
            end)
        local consumedWidth = type(slotWidth) == "number" and slotWidth or math.max(contentWidth, (drawX - slotX) + contentWidth)
        return consumedWidth, consumedHeight, changed
    end,
}

WidgetTypes.button = {
    binds = {},
    slots = { "control" },
    validate = function(node, prefix)
        PrepareWidgetText(node)
        if node._label == "" then
            libWarn("%s: button requires non-empty label", prefix)
        end
        if node.onClick ~= nil and type(node.onClick) ~= "function" then
            libWarn("%s: button onClick must be function", prefix)
        end
    end,
    draw = function(imgui, node, _, x, y, _, _, uiState)
        local label = (node._label or "") .. (node._imguiId or "")
        local contentWidth = EstimateButtonWidth(imgui, node._label or "")
        local slotX, drawX, slotWidth = ResolveSingleSlotPlacement(node, "control", x, contentWidth)
        local changed, _, _, consumedHeight = DrawStructuredAt(
            imgui,
            slotX,
            y,
            EstimateStructuredRowAdvanceY(imgui),
            function()
                if drawX ~= slotX then
                    if type(imgui.SetCursorPosX) == "function" then
                        imgui.SetCursorPosX(drawX)
                    else
                        SetCursorPosSafe(imgui, drawX, y)
                    end
                end
                if imgui.Button(label) then
                    ShowPreparedTooltip(imgui, node)
                    return true
                end
                ShowPreparedTooltip(imgui, node)
                return false
            end)
        local consumedWidth = type(slotWidth) == "number" and slotWidth or math.max(contentWidth, (drawX - slotX) + contentWidth)
        if changed and type(node.onClick) == "function" then
            node.onClick(uiState, node, imgui)
        end
        return consumedWidth, consumedHeight, changed
    end,
}

WidgetTypes.confirmButton = {
    binds = {},
    slots = { "control" },
    validate = function(node, prefix)
        PrepareWidgetText(node)
        if node._label == "" then
            libWarn("%s: confirmButton requires non-empty label", prefix)
        end
        if node.onConfirm ~= nil and type(node.onConfirm) ~= "function" then
            libWarn("%s: confirmButton onConfirm must be function", prefix)
        end
        if node.confirmLabel ~= nil and type(node.confirmLabel) ~= "string" then
            libWarn("%s: confirmButton confirmLabel must be string", prefix)
        end
        if node.cancelLabel ~= nil and type(node.cancelLabel) ~= "string" then
            libWarn("%s: confirmButton cancelLabel must be string", prefix)
        end
        node._confirmLabel = type(node.confirmLabel) == "string" and node.confirmLabel ~= "" and node.confirmLabel or "Confirm"
        node._cancelLabel = type(node.cancelLabel) == "string" and node.cancelLabel ~= "" and node.cancelLabel or "Cancel"
        node._confirmPopupId = (node._imguiId or "confirmButton") .. "##popup"
    end,
    draw = function(imgui, node, _, x, y, _, _, uiState)
        local state = node._confirmButtonState or {}
        state.uiState = uiState
        node._confirmButtonState = state

        local contentWidth = EstimateButtonWidth(imgui, node._label or "")
        local slotX, drawX, slotWidth = ResolveSingleSlotPlacement(node, "control", x, contentWidth)
        local changed, _, _, consumedHeight = DrawStructuredAt(
            imgui,
            slotX,
            y,
            EstimateStructuredRowAdvanceY(imgui),
            function()
                if drawX ~= slotX then
                    if type(imgui.SetCursorPosX) == "function" then
                        imgui.SetCursorPosX(drawX)
                    else
                        SetCursorPosSafe(imgui, drawX, y)
                    end
                end

                if imgui.Button((node._label or "") .. (node._imguiId or "")) then
                    node._confirmButtonState = state
                    if type(imgui.OpenPopup) == "function" then
                        imgui.OpenPopup(node._confirmPopupId)
                    end
                end
                ShowPreparedTooltip(imgui, node)

                local popupChanged = false
                if type(imgui.BeginPopup) == "function" and imgui.BeginPopup(node._confirmPopupId) then
                    if imgui.Button(node._confirmLabel .. (node._imguiId or "")) then
                        node._confirmButtonState = state
                        if type(node.onConfirm) == "function" then
                            node.onConfirm(state.uiState, node, imgui)
                        end
                        if type(imgui.CloseCurrentPopup) == "function" then
                            imgui.CloseCurrentPopup()
                        end
                        popupChanged = true
                    end
                    if type(imgui.SameLine) == "function" then
                        imgui.SameLine()
                    end
                    if imgui.Button(node._cancelLabel .. "##cancel" .. (node._imguiId or "")) then
                        node._confirmButtonState = state
                        if type(imgui.CloseCurrentPopup) == "function" then
                            imgui.CloseCurrentPopup()
                        end
                    end
                    if type(imgui.EndPopup) == "function" then
                        imgui.EndPopup()
                    end
                end

                return popupChanged
            end)
        local consumedWidth = type(slotWidth) == "number" and slotWidth or math.max(contentWidth, (drawX - slotX) + contentWidth)
        return consumedWidth, consumedHeight, changed
    end,
}

WidgetTypes.inputText = {
    binds = { value = { storageType = "string" } },
    slots = { "label", "control" },
    validate = function(node, prefix)
        if node.maxLen ~= nil and (type(node.maxLen) ~= "number" or node.maxLen < 1) then
            libWarn("%s: inputText maxLen must be a positive number", prefix)
        end
        node._maxLen = math.floor(tonumber(node.maxLen) or 0)
        if node._maxLen < 1 then
            node._maxLen = nil
        end
        PrepareWidgetText(node, node.binds and node.binds.value)
    end,
    validateGeometry = function(_, prefix, geometry)
        WarnIgnoredSlotKeys(prefix, geometry, "control", { "align" }, "inputText")
    end,
    draw = function(imgui, node, bound, x, y, availWidth)
        local aliasNode = bound.value and bound.value.node or nil
        local ctx = node._inputTextCtx or {}
        ctx.boundValue = bound.value
        ctx.current = tostring(bound.value:get() or "")
        ctx.maxLen = node._maxLen or (aliasNode and aliasNode._maxLen) or 256
        node._inputTextCtx = ctx

        local labelText = node._label or ""
        local hasLabel = labelText ~= ""
        local labelWidth = hasLabel and CalcTextWidth(imgui, labelText) or 0
        local controlGeometry = GetSlotGeometry(node, "control")
        local controlWidth = controlGeometry and controlGeometry.width or availWidth or 120
        local controlStart = controlGeometry and controlGeometry.start or nil
        local itemSpacingX = GetStyleMetricX(imgui.GetStyle(), "ItemSpacing", 8)

        local controlSlotX
        if type(controlStart) == "number" then
            controlSlotX = x + controlStart
        elseif hasLabel then
            controlSlotX = x + labelWidth + itemSpacingX
        else
            controlSlotX = x
        end

        local maxHeight = 0
        local changed = false

        if hasLabel then
            local _, _, _, labelHeight = DrawStructuredAt(
                imgui,
                x,
                y,
                EstimateStructuredRowAdvanceY(imgui),
                function()
                    imgui.Text(labelText)
                    ShowPreparedTooltip(imgui, node)
                    return false
                end)
            if type(labelHeight) == "number" and labelHeight > maxHeight then
                maxHeight = labelHeight
            end
        end

        local controlChanged, _, _, controlHeight = DrawStructuredAt(
            imgui,
            controlSlotX,
            y,
            EstimateStructuredRowAdvanceY(imgui),
            function()
                if type(controlWidth) == "number" and controlWidth > 0 then
                    imgui.PushItemWidth(controlWidth)
                end
                local newValue, widgetChanged = imgui.InputText(node._imguiId, ctx.current or "", ctx.maxLen)
                if type(controlWidth) == "number" and controlWidth > 0 then
                    imgui.PopItemWidth()
                end
                ShowPreparedTooltip(imgui, node)
                if widgetChanged then
                    ctx.boundValue:set(newValue)
                    return true
                end
                return false
            end)
        if controlChanged then
            changed = true
        end
        if type(controlHeight) == "number" and controlHeight > maxHeight then
            maxHeight = controlHeight
        end

        local consumedWidth
        if type(controlGeometry) == "table" and type(controlGeometry.width) == "number" then
            consumedWidth = math.max((controlSlotX - x) + controlGeometry.width, hasLabel and labelWidth or 0)
        elseif type(controlWidth) == "number" then
            consumedWidth = math.max((controlSlotX - x) + controlWidth, hasLabel and labelWidth or 0)
        else
            consumedWidth = math.max((controlSlotX - x), hasLabel and labelWidth or 0)
        end

        return consumedWidth, maxHeight, changed
    end,
}

local function DrawLabeledDropdownControl(imgui, node, x, y, availWidth, estimatedControlWidth, drawControl)
    local labelText = node._label or ""
    local hasLabel = labelText ~= ""
    local labelWidth = hasLabel and CalcTextWidth(imgui, labelText) or 0
    local controlGeometry = GetSlotGeometry(node, "control")
    local controlWidth = controlGeometry and controlGeometry.width or availWidth or estimatedControlWidth
    local controlStart = controlGeometry and controlGeometry.start or nil
    local itemSpacingX = GetStyleMetricX(imgui.GetStyle(), "ItemSpacing", 8)

    local controlSlotX
    if type(controlStart) == "number" then
        controlSlotX = x + controlStart
    elseif hasLabel then
        controlSlotX = x + labelWidth + itemSpacingX
    else
        controlSlotX = x
    end

    local maxHeight = 0
    local changed = false

    if hasLabel then
        local _, _, _, labelHeight = DrawStructuredAt(
            imgui,
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui),
            function()
                imgui.Text(labelText)
                ShowPreparedTooltip(imgui, node)
                return false
            end)
        if type(labelHeight) == "number" and labelHeight > maxHeight then
            maxHeight = labelHeight
        end
    end

    local controlChanged, _, _, controlHeight = DrawStructuredAt(
        imgui,
        controlSlotX,
        y,
        EstimateStructuredRowAdvanceY(imgui),
        function()
            if type(controlWidth) == "number" and controlWidth > 0 then
                imgui.PushItemWidth(controlWidth)
            end
            local widgetChanged = drawControl(controlWidth)
            if type(controlWidth) == "number" and controlWidth > 0 then
                imgui.PopItemWidth()
            end
            ShowPreparedTooltip(imgui, node)
            return widgetChanged == true
        end)
    if controlChanged then
        changed = true
    end
    if type(controlHeight) == "number" and controlHeight > maxHeight then
        maxHeight = controlHeight
    end

    local consumedWidth
    if type(controlGeometry) == "table" and type(controlGeometry.width) == "number" then
        consumedWidth = math.max((controlSlotX - x) + controlGeometry.width, hasLabel and labelWidth or 0)
    elseif type(controlWidth) == "number" then
        consumedWidth = math.max((controlSlotX - x) + controlWidth, hasLabel and labelWidth or 0)
    else
        consumedWidth = math.max((controlSlotX - x) + estimatedControlWidth, hasLabel and labelWidth or 0)
    end

    return consumedWidth, maxHeight, changed
end

local function BuildOrderedChoiceEntries(node, options)
    options = options or {}
    local geometryOwner = options.geometryOwner or node
    local labelText = options.labelText
    if labelText == nil then
        labelText = node._label or ""
    end
    local labelSlotName = options.labelSlotName or "label"
    local firstOptionSameLine = options.firstOptionSameLine
    if firstOptionSameLine == nil then
        firstOptionSameLine = labelText ~= ""
    end
    local entries = {}

    local function AddEntry(name, config)
        local geometry = type(name) == "string" and GetSlotGeometry(geometryOwner, name) or nil
        entries[#entries + 1] = {
            index = #entries + 1,
            name = name,
            line = (geometry and geometry.line) or config.line or 1,
            start = (geometry and geometry.start) or config.start,
            width = (geometry and geometry.width) or config.width,
            align = (geometry and geometry.align) or config.align,
            sameLine = config.sameLine,
            estimateWidth = config.estimateWidth,
            render = config.render,
        }
    end

    if labelText ~= "" then
        AddEntry(labelSlotName, {
            estimateWidth = function(imgui)
                return CalcTextWidth(imgui, labelText)
            end,
            render = function(imgui)
                imgui.Text(labelText)
                ShowPreparedTooltip(imgui, node)
                return false, CalcTextWidth(imgui, labelText), EstimateStructuredRowAdvanceY(imgui)
            end,
        })
    end

    for index, option in ipairs(options.optionEntries or {}) do
        local slotName = option.slotName or ("option:" .. tostring(index))
        local sameLine = option.sameLine
        if sameLine == nil then
            sameLine = index > 1 or firstOptionSameLine
        end
        AddEntry(slotName, {
            sameLine = sameLine,
            line = option.line,
            start = option.start,
            width = option.width,
            align = option.align,
            estimateWidth = function(imgui)
                return EstimateToggleWidth(imgui, option.label)
            end,
            render = function(imgui)
                local clicked = DrawWithValueColor(imgui, option.color, function()
                    return imgui.RadioButton(option.label, option.selected == true)
                end)
                if clicked and type(option.onSelect) == "function" then
                    return option.onSelect() == true, EstimateToggleWidth(imgui, option.label), EstimateStructuredRowAdvanceY(imgui)
                end
                return false, EstimateToggleWidth(imgui, option.label), EstimateStructuredRowAdvanceY(imgui)
            end,
        })
    end

    table.sort(entries, function(left, right)
        if left.line ~= right.line then
            return left.line < right.line
        end
        if type(left.start) == "number" and type(right.start) == "number" and left.start ~= right.start then
            return left.start < right.start
        end
        return left.index < right.index
    end)

    return entries
end

local function BuildOrderedCheckboxEntries(node, optionEntries, options)
    options = options or {}
    local geometryOwner = options.geometryOwner or node
    local entries = {}

    local function AddEntry(name, config)
        local geometry = type(name) == "string" and GetSlotGeometry(geometryOwner, name) or nil
        entries[#entries + 1] = {
            index = #entries + 1,
            name = name,
            line = (geometry and geometry.line) or config.line or 1,
            start = (geometry and geometry.start) or config.start,
            width = (geometry and geometry.width) or config.width,
            align = (geometry and geometry.align) or config.align,
            sameLine = config.sameLine,
            estimateWidth = config.estimateWidth,
            render = config.render,
        }
    end

    for index, option in ipairs(optionEntries or {}) do
        local slotName = option.slotName or ("item:" .. tostring(index))
        AddEntry(slotName, {
            sameLine = option.sameLine,
            line = option.line,
            start = option.start,
            width = option.width,
            align = option.align,
            estimateWidth = function(imgui)
                return EstimateToggleWidth(imgui, option.label)
            end,
            render = function(imgui)
                imgui.PushID((slotName or "item") .. "_" .. tostring(index))
                local nextValue, clicked = DrawWithValueColor(imgui, option.color, function()
                    return imgui.Checkbox(option.label, option.current == true)
                end)
                imgui.PopID()
                if clicked and type(option.onToggle) == "function" then
                    return option.onToggle(nextValue) == true,
                        EstimateToggleWidth(imgui, option.label),
                        EstimateStructuredRowAdvanceY(imgui)
                end
                return false, EstimateToggleWidth(imgui, option.label), EstimateStructuredRowAdvanceY(imgui)
            end,
        })
    end

    table.sort(entries, function(left, right)
        if left.line ~= right.line then
            return left.line < right.line
        end
        if type(left.start) == "number" and type(right.start) == "number" and left.start ~= right.start then
            return left.start < right.start
        end
        return left.index < right.index
    end)

    return entries
end

WidgetTypes.dropdown = {
    binds = { value = { storageType = { "string", "int" } } },
    slots = { "label", "control" },
    validate = function(node, prefix)
        if not node.values then
            libWarn("%s: dropdown missing values list", prefix)
        elseif type(node.values) ~= "table" or #node.values == 0 then
            libWarn("%s: dropdown values must be a non-empty list", prefix)
        else
            for _, value in ipairs(node.values) do
                if type(value) == "string" and string.find(value, "|", 1, true) then
                    libWarn("%s: value '%s' contains reserved separator '|'", prefix, value)
                elseif type(value) ~= "string" and (type(value) ~= "number" or value ~= math.floor(value)) then
                    libWarn("%s: dropdown values must contain only strings or integers", prefix)
                end
            end
        end
        if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
            libWarn("%s: dropdown displayValues must be a table", prefix)
        end
        ValidateValueColorsTable(node, prefix, "dropdown")
        PrepareWidgetText(node, node.binds and node.binds.value)
    end,
    draw = function(imgui, node, bound, x, y, availWidth)
        local current = NormalizeChoiceValue(node, bound.value:get())
        local currentIdx = 1
        for index, candidate in ipairs(node.values or {}) do
            if candidate == current then currentIdx = index; break end
        end

        local ctx = node._dropdownCtx or {}
        ctx.boundValue = bound.value
        ctx.current = current
        ctx.currentIdx = currentIdx
        ctx.previewValue = (node.values and node.values[currentIdx]) or ""
        node._dropdownCtx = ctx
        local previewText = ChoiceDisplay(node, ctx.previewValue or "")
        local previewColor = node._valueColors and node._valueColors[ctx.previewValue] or nil
        local estimatedControlWidth = EstimateButtonWidth(imgui, previewText) + 16

        return DrawLabeledDropdownControl(
            imgui,
            node,
            x,
            y,
            availWidth,
            estimatedControlWidth,
            function()
                local opened = DrawWithValueColor(imgui, previewColor, function()
                    return imgui.BeginCombo(node._imguiId, previewText)
                end)
                if not opened then
                    return false
                end

                local changed = false
                local pendingValue = nil
                for index, candidate in ipairs(node.values or {}) do
                    local optionColor = node._valueColors and node._valueColors[candidate] or nil
                    local selected = DrawWithValueColor(imgui, optionColor, function()
                        return imgui.Selectable(
                            MakeSelectableId(ChoiceDisplay(node, candidate), index),
                            false)
                    end)
                    if selected and candidate ~= ctx.current then
                        pendingValue = candidate
                    end
                end
                imgui.EndCombo()
                if pendingValue ~= nil then
                    ctx.boundValue:set(pendingValue)
                    changed = true
                end
                return changed
            end)
    end,
}

WidgetTypes.mappedDropdown = {
    binds = { value = {} },
    slots = { "label", "control" },
    validate = function(node, prefix)
        if type(node.getPreview) ~= "function" then
            libWarn("%s: mappedDropdown getPreview must be function", prefix)
        end
        if type(node.getOptions) ~= "function" then
            libWarn("%s: mappedDropdown getOptions must be function", prefix)
        end
        if node.getPreviewColor ~= nil and type(node.getPreviewColor) ~= "function" then
            libWarn("%s: mappedDropdown getPreviewColor must be function", prefix)
        end
        PrepareWidgetText(node, node.binds and node.binds.value)
    end,
    validateGeometry = function(node, prefix, geometry)
        local _ = node
        WarnIgnoredSlotKeys(prefix, geometry, "label", { "width", "align" }, "mappedDropdown")
    end,
    draw = function(imgui, node, bound, x, y, availWidth, _, uiState)
        local ctx = node._mappedDropdownCtx or {}
        ctx.boundValue = bound.value
        ctx.current = bound.value and bound.value.get and bound.value:get() or nil
        ctx.uiState = uiState
        ctx.preview = type(node.getPreview) == "function"
            and tostring(node.getPreview(node, bound, uiState) or "")
            or ""
        ctx.previewColor = type(node.getPreviewColor) == "function"
            and node.getPreviewColor(node, bound, uiState)
            or nil
        ctx.options = type(node.getOptions) == "function"
            and node.getOptions(node, bound, uiState)
            or {}
        node._mappedDropdownCtx = ctx
        local estimatedControlWidth = EstimateButtonWidth(imgui, ctx.preview or "") + 16
        return DrawLabeledDropdownControl(
            imgui,
            node,
            x,
            y,
            availWidth,
            estimatedControlWidth,
            function()
                local opened = DrawWithValueColor(imgui, ctx.previewColor, function()
                    return imgui.BeginCombo(node._imguiId, ctx.preview or "")
                end)
                if not opened then
                    return false
                end

                local changed = false
                for _, option in ipairs(ctx.options or {}) do
                    local label
                    if type(option) == "table" then
                        label = tostring(option.label or option.value or "")
                    else
                        label = tostring(option or "")
                    end

                    local optionColor = type(option) == "table" and option.color or nil
                    local clicked = DrawWithValueColor(imgui, optionColor, function()
                        local uniqueId = type(option) == "table"
                            and (option.id or option.value or label)
                            or option
                        return imgui.Selectable(MakeSelectableId(label, uniqueId), false)
                    end)
                    if clicked then
                        if type(option) == "table" and type(option.onSelect) == "function" then
                            changed = option.onSelect(option, ctx.boundValue, ctx.uiState, node) == true or changed
                        else
                            local nextValue = type(option) == "table" and option.value or option
                            if nextValue ~= ctx.current then
                                ctx.boundValue:set(nextValue)
                                changed = true
                            end
                        end
                    end
                end

                imgui.EndCombo()
                return changed
            end)
    end,
}

WidgetTypes.packedDropdown = {
    binds = { value = { storageType = "int", rootType = "packedInt" } },
    slots = { "label", "control" },
    validate = function(node, prefix)
        PrepareWidgetText(node, node.binds and node.binds.value)
        ValidatePackedChoiceWidget(node, prefix, "packedDropdown")
    end,
    validateGeometry = function(node, prefix, geometry)
        local _ = node
        WarnIgnoredSlotKeys(prefix, geometry, "label", { "width", "align" }, "packedDropdown")
    end,
    draw = function(imgui, node, bound, x, y, availWidth)
        local children = GetPackedChoiceChildren(node, bound, "packedDropdown")
        if not children then
            return 0, 0, false
        end

        local selection = ClassifyPackedChoice(node, children)
        local ctx = node._packedDropdownCtx or {}
        ctx.children = children
        ctx.selection = selection
        ctx.noneLabel = node.noneLabel or "None"
        ctx.multipleLabel = node.multipleLabel or "Multiple"
        if selection.state == "single" and selection.selectedChild then
            ctx.preview = GetPackedChoiceLabel(node, selection.selectedChild)
            ctx.previewColor = node._valueColors and node._valueColors[selection.selectedChild.alias] or nil
        elseif selection.state == "multiple" then
            ctx.preview = ctx.multipleLabel
            ctx.previewColor = nil
        else
            ctx.preview = ctx.noneLabel
            ctx.previewColor = nil
        end
        node._packedDropdownCtx = ctx
        local estimatedControlWidth = EstimateButtonWidth(imgui, ctx.preview or "") + 16
        return DrawLabeledDropdownControl(
            imgui,
            node,
            x,
            y,
            availWidth,
            estimatedControlWidth,
            function()
                local opened = DrawWithValueColor(imgui, ctx.previewColor, function()
                    return imgui.BeginCombo(node._imguiId, ctx.preview or "")
                end)
                if not opened then
                    return false
                end

                local changed = false
                local pendingClear = false
                local pendingAlias = nil
                if imgui.Selectable(MakeSelectableId(ctx.noneLabel or "None", "none"), false) then
                    pendingClear = true
                end

                for _, child in ipairs(ctx.children or {}) do
                    local optionColor = node._valueColors and node._valueColors[child.alias] or nil
                    local clicked = DrawWithValueColor(imgui, optionColor, function()
                        return imgui.Selectable(
                            MakeSelectableId(GetPackedChoiceLabel(node, child), child.alias),
                            false)
                    end)
                    if clicked then
                        pendingClear = false
                        pendingAlias = child.alias
                    end
                end

                imgui.EndCombo()
                if pendingAlias ~= nil then
                    changed = ApplyPackedChoiceSelection(ctx.children, pendingAlias, ctx.selection) or changed
                elseif pendingClear then
                    changed = ClearPackedChoiceSelection(ctx.children, ctx.selection) or changed
                end
                return changed
            end)
    end,
}

WidgetTypes.radio = {
    binds = { value = { storageType = { "string", "int" } } },
    slots = { "label" },
    dynamicSlots = function(node, slotName)
        local optionIndex = type(slotName) == "string" and tonumber(string.match(slotName, "^option:(%d+)$")) or nil
        if optionIndex == nil then
            return false, nil
        end
        local optionCount = type(node.values) == "table" and #node.values or 0
        if optionIndex < 1 or optionIndex > optionCount then
            return false, ("geometry slot '%s' is out of range for %d radio options"):format(
                tostring(slotName), optionCount)
        end
        return true, nil
    end,
    validate = function(node, prefix)
        if not node.values then
            libWarn("%s: radio missing values list", prefix)
        elseif type(node.values) ~= "table" or #node.values == 0 then
            libWarn("%s: radio values must be a non-empty list", prefix)
        else
            for _, value in ipairs(node.values) do
                if type(value) == "string" and string.find(value, "|", 1, true) then
                    libWarn("%s: value '%s' contains reserved separator '|'", prefix, value)
                elseif type(value) ~= "string" and (type(value) ~= "number" or value ~= math.floor(value)) then
                    libWarn("%s: radio values must contain only strings or integers", prefix)
                end
            end
        end
        if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
            libWarn("%s: radio displayValues must be a table", prefix)
        end
        ValidateValueColorsTable(node, prefix, "radio")
        PrepareWidgetText(node, node.binds and node.binds.value)
    end,
    validateGeometry = function(node, prefix, geometry)
        local _ = node
        WarnIgnoredSlotKeys(prefix, geometry, "label", { "width", "align" }, "radio")
        WarnIgnoredDynamicSlotKeys(prefix, geometry, "^option:%d+$", { "width", "align" }, "radio")
    end,
    draw = function(imgui, node, bound, x, y)
        local ctx = node._radioCtx or {}
        ctx.boundValue = bound.value
        ctx.current = NormalizeChoiceValue(node, bound.value:get())
        node._radioCtx = ctx
        local optionEntries = {}
        for index, candidate in ipairs(node.values or {}) do
            optionEntries[#optionEntries + 1] = {
                slotName = "option:" .. tostring(index),
                label = ChoiceDisplay(node, candidate),
                color = node._valueColors and node._valueColors[candidate] or nil,
                selected = ctx.current == candidate,
                onSelect = function()
                    if candidate ~= ctx.current then
                        ctx.boundValue:set(candidate)
                        ctx.current = candidate
                        return true
                    end
                    return false
                end,
            }
        end
        return DrawOrderedEntries(
            imgui,
            BuildOrderedChoiceEntries(node, {
                optionEntries = optionEntries,
            }),
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui))
    end,
}

WidgetTypes.mappedRadio = {
    binds = { value = {} },
    slots = { "label" },
    dynamicSlots = function(_, slotName)
        local optionIndex = type(slotName) == "string" and tonumber(string.match(slotName, "^option:(%d+)$")) or nil
        if optionIndex ~= nil and optionIndex >= 1 then
            return true, nil
        end
        return false, nil
    end,
    validate = function(node, prefix)
        if type(node.getOptions) ~= "function" then
            libWarn("%s: mappedRadio getOptions must be function", prefix)
        end
        PrepareWidgetText(node, node.binds and node.binds.value)
    end,
    validateGeometry = function(node, prefix, geometry)
        local _ = node
        WarnIgnoredSlotKeys(prefix, geometry, "label", { "width", "align" }, "mappedRadio")
        WarnIgnoredDynamicSlotKeys(prefix, geometry, "^option:%d+$", { "width", "align" }, "mappedRadio")
    end,
    draw = function(imgui, node, bound, x, y, _, _, uiState)
        local ctx = node._mappedRadioCtx or {}
        ctx.boundValue = bound.value
        ctx.current = bound.value and bound.value.get and bound.value:get() or nil
        ctx.uiState = uiState
        ctx.options = type(node.getOptions) == "function"
            and node.getOptions(node, bound, uiState)
            or {}
        node._mappedRadioCtx = ctx

        local optionEntries = {}
        for index, option in ipairs(ctx.options or {}) do
            local label
            local selected
            if type(option) == "table" then
                label = tostring(option.label or option.value or "")
                selected = option.selected == true
            else
                label = tostring(option or "")
                selected = ctx.current ~= nil and option == ctx.current or false
            end
            optionEntries[#optionEntries + 1] = {
                slotName = "option:" .. tostring(index),
                label = label,
                selected = selected,
                onSelect = function()
                    if type(option) == "table" and type(option.onSelect) == "function" then
                        return option.onSelect(option, ctx.boundValue, ctx.uiState, node) == true
                    end

                    local nextValue = type(option) == "table" and option.value or option
                    if nextValue ~= ctx.current then
                        ctx.boundValue:set(nextValue)
                        ctx.current = nextValue
                        return true
                    end
                    return false
                end,
            }
        end

        return DrawOrderedEntries(
            imgui,
            BuildOrderedChoiceEntries(node, {
                optionEntries = optionEntries,
            }),
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui))
    end,
}

WidgetTypes.packedRadio = {
    binds = { value = { storageType = "int", rootType = "packedInt" } },
    slots = { "label" },
    dynamicSlots = function(_, slotName)
        if slotName == "option:none" then
            return true, nil
        end
        local optionIndex = type(slotName) == "string" and tonumber(string.match(slotName, "^option:(%d+)$")) or nil
        if optionIndex ~= nil and optionIndex >= 1 then
            return true, nil
        end
        return false, nil
    end,
    validate = function(node, prefix)
        PrepareWidgetText(node, node.binds and node.binds.value)
        ValidatePackedChoiceWidget(node, prefix, "packedRadio")
    end,
    validateGeometry = function(node, prefix, geometry)
        local _ = node
        WarnIgnoredSlotKeys(prefix, geometry, "label", { "width", "align" }, "packedRadio")
        WarnIgnoredDynamicSlotKeys(prefix, geometry, "^option:(none|%d+)$", { "width", "align" }, "packedRadio")
    end,
    draw = function(imgui, node, bound, x, y)
        local children = GetPackedChoiceChildren(node, bound, "packedRadio")
        if not children then
            return 0, 0, false
        end

        local selection = ClassifyPackedChoice(node, children)
        local optionEntries = {
            {
                slotName = "option:none",
                label = node.noneLabel or "None",
                selected = selection.state == "none",
                onSelect = function()
                    return ClearPackedChoiceSelection(children, selection) == true
                end,
            },
        }
        for index, child in ipairs(children) do
            optionEntries[#optionEntries + 1] = {
                slotName = "option:" .. tostring(index),
                label = GetPackedChoiceLabel(node, child),
                color = node._valueColors and node._valueColors[child.alias] or nil,
                selected = selection.selectedChild and selection.selectedChild.alias == child.alias or false,
                onSelect = function()
                    return ApplyPackedChoiceSelection(children, child.alias, selection) == true
                end,
            }
        end

        return DrawOrderedEntries(
            imgui,
            BuildOrderedChoiceEntries(node, {
                optionEntries = optionEntries,
            }),
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui))
    end,
}

local function ValidateStepper(node, prefix)
    StorageTypes.int.validate(node, prefix)
    if node.step ~= nil and (type(node.step) ~= "number" or node.step <= 0) then
        libWarn("%s: stepper step must be a positive number", prefix)
    end
    if node.fastStep ~= nil and (type(node.fastStep) ~= "number" or node.fastStep <= 0) then
        libWarn("%s: stepper fastStep must be a positive number", prefix)
    end
    if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
        libWarn("%s: stepper displayValues must be a table", prefix)
    end
    ValidateValueColorsTable(node, prefix, "stepper")
    node._step = math.floor(tonumber(node.step) or 1)
    node._fastStep = node.fastStep and math.floor(node.fastStep) or nil
    PrepareWidgetText(node, node.binds and node.binds.value)
end

WidgetTypes.stepper = {
    binds = { value = { storageType = "int" } },
    slots = { "label", "decrement", "value", "increment", "fastDecrement", "fastIncrement" },
    validate = ValidateStepper,
    draw = function(imgui, node, bound, x, y)
        PrepareStepperDrawContext(node, bound.value)
        return DrawOrderedEntries(
            imgui,
            BuildOrderedStepperEntries(node),
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui))
    end,
}

WidgetTypes.steppedRange = {
    binds = {
        min = { storageType = "int" },
        max = { storageType = "int" },
    },
    slots = {
        "label",
        "min.decrement", "min.value", "min.increment", "min.fastDecrement", "min.fastIncrement",
        "separator",
        "max.decrement", "max.value", "max.increment", "max.fastDecrement", "max.fastIncrement",
    },
    validate = function(node, prefix)
        local minStepper = {
            label = node.label,
            default = node.default,
            min = node.min, max = node.max,
            step = node.step, fastStep = node.fastStep,
        }
        local maxStepper = {
            default = node.defaultMax or node.default,
            min = node.min, max = node.max,
            step = node.step, fastStep = node.fastStep,
        }
        ValidateStepper(minStepper, prefix .. " min")
        ValidateStepper(maxStepper, prefix .. " max")
        node._minStepper = minStepper
        node._maxStepper = maxStepper
    end,
    draw = function(imgui, node, bound, x, y)
        local minStepper = node._minStepper
        local maxStepper = node._maxStepper
        if not minStepper or not maxStepper then
            libWarn("steppedRange '%s' not prepared", tostring(node.binds and node.binds.min or node.type))
            return 0, 0, false
        end

        local minValue = bound.min:get()
        local maxValue = bound.max:get()

        PrepareStepperDrawContext(minStepper, bound.min, { min = minStepper.min, max = maxValue })
        PrepareStepperDrawContext(maxStepper, bound.max, { min = minValue, max = maxStepper.max })
        local entries = BuildOrderedStepperEntries(minStepper, {
            drawLabel = true,
            slotPrefix = "min.",
            labelSlotName = "label",
            geometryOwner = node,
        })
        local separatorGeometry = GetSlotGeometry(node, "separator")
        entries[#entries + 1] = {
            index = #entries + 1,
            name = "separator",
            line = (separatorGeometry and separatorGeometry.line) or 1,
            start = separatorGeometry and separatorGeometry.start or nil,
            width = separatorGeometry and separatorGeometry.width or nil,
            align = separatorGeometry and separatorGeometry.align or nil,
            sameLine = true,
            estimateWidth = function(_imgui)
                return CalcTextWidth(_imgui, "to")
            end,
            render = function(_imgui)
                _imgui.Text("to")
                return false, CalcTextWidth(_imgui, "to"), EstimateStructuredRowAdvanceY(_imgui)
            end,
        }
        local maxEntries = BuildOrderedStepperEntries(maxStepper, {
            drawLabel = false,
            slotPrefix = "max.",
            firstSlotSameLine = true,
            geometryOwner = node,
        })
        for _, entry in ipairs(maxEntries) do
            entry.index = #entries + 1
            entries[#entries + 1] = entry
        end
        for index, entry in ipairs(entries) do
            entry.index = index
        end
        table.sort(entries, function(left, right)
            if left.line ~= right.line then
                return left.line < right.line
            end
            if type(left.start) == "number" and type(right.start) == "number" and left.start ~= right.start then
                return left.start < right.start
            end
            return left.index < right.index
        end)
        return DrawOrderedEntries(
            imgui,
            entries,
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui))
    end,
}

WidgetTypes.packedCheckboxList = {
    binds = {
        value = { storageType = "int", rootType = "packedInt" },
        filterText = { storageType = "string", optional = true },
        filterMode = { storageType = "string", optional = true },
    },
    dynamicSlots = function(node, slotName)
        local itemIndex = type(slotName) == "string" and tonumber(string.match(slotName, "^item:(%d+)$")) or nil
        if itemIndex == nil then
            return false, nil
        end
        local slotCount = tonumber(node.slotCount) or DEFAULT_PACKED_SLOT_COUNT
        slotCount = math.floor(slotCount)
        if itemIndex < 1 or itemIndex > slotCount then
            return false, ("geometry slot '%s' is out of range for packedCheckboxList slotCount %d"):format(
                tostring(slotName), slotCount)
        end
        return true, nil
    end,
    validate = function(node, prefix)
        if node.slotCount == nil then
            node.slotCount = DEFAULT_PACKED_SLOT_COUNT
        elseif type(node.slotCount) ~= "number" then
            libWarn("%s: packedCheckboxList slotCount must be a number", prefix)
            node.slotCount = DEFAULT_PACKED_SLOT_COUNT
        elseif node.slotCount < 1 or math.floor(node.slotCount) ~= node.slotCount then
            libWarn("%s: packedCheckboxList slotCount must be a positive integer", prefix)
            node.slotCount = DEFAULT_PACKED_SLOT_COUNT
        else
            node.slotCount = math.floor(node.slotCount)
        end

        ValidateValueColorsTable(node, prefix, "packedCheckboxList")

        -- packedCheckboxList renders items directly in draw(), but it still needs
        -- stable per-item slot descriptors so static geometry can target
        -- item:N consistently without rebuilding slot metadata every frame.
        node._packedSlots = BuildIndexedSlots(node.slotCount, function(index)
            return {
                name = "item:" .. tostring(index),
                line = index,
            }
        end)
    end,
    validateGeometry = function(node, prefix, geometry)
        local _ = node
        WarnIgnoredDynamicSlotKeys(prefix, geometry, "^item:%d+$", { "width", "align" }, "packedCheckboxList")
    end,
    draw = function(imgui, node, bound, x, y)
        local children = bound.value and bound.value.children
        if not children or #children == 0 then
            libWarn("packedCheckboxList: no packed children for alias '%s'; bind to a packedInt root",
                tostring(node.binds and node.binds.value or "?"))
            return 0, 0, false
        end

        local filterBind = bound.filterText
        local filterText = filterBind and filterBind.get() or ""
        if type(filterText) ~= "string" then filterText = "" end
        local lowerFilter = filterText:lower()
        local hasFilter = lowerFilter ~= ""
        local filterModeBind = bound.filterMode
        local filterMode = filterModeBind and filterModeBind.get() or "all"
        if filterMode ~= "checked" and filterMode ~= "unchecked" then
            filterMode = "all"
        end
        local visibleIndex = 0
        local optionEntries = {}

        for _, child in ipairs(children) do
            if child ~= nil then
                local label = child.label or ""
                local val = child.get()
                if val == nil then val = false end
                local matchesText = not hasFilter or label:lower():find(lowerFilter, 1, true) ~= nil
                local matchesMode = filterMode == "all"
                    or (filterMode == "checked" and val == true)
                    or (filterMode == "unchecked" and val ~= true)
                local visible = matchesText and matchesMode
                if visible and visibleIndex < node.slotCount then
                    visibleIndex = visibleIndex + 1
                    local slot = node._packedSlots[visibleIndex]
                    optionEntries[#optionEntries + 1] = {
                        slotName = slot.name,
                        sameLine = slot.sameLine,
                        line = slot.line,
                        start = slot.start,
                        label = label,
                        current = val == true,
                        color = node._valueColors and node._valueColors[child.alias] or nil,
                        onToggle = function(nextValue)
                            child.set(nextValue)
                            return true
                        end,
                    }
                end
            end
        end

        return DrawOrderedEntries(
            imgui,
            BuildOrderedCheckboxEntries(node, optionEntries),
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui))
    end,
}
