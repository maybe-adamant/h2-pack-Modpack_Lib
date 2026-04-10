local internal = AdamantModpackLib_Internal
local shared = internal.shared
local libWarn = shared.libWarn

shared.fieldRegistry = shared.fieldRegistry or {}

import 'field_registry/shared.lua'
import 'field_registry/storage.lua'
import 'field_registry/widgets.lua'
import 'field_registry/layouts.lua'
import 'field_registry/ui.lua'

function public.drawWidgetSlots(imgui, node, slots, rowStart)
    local registry = shared.fieldRegistry or {}
    local drawWidgetSlots = registry.DrawWidgetSlots
    local getCursorPosXSafe = registry.GetCursorPosXSafe
    local prepareLooseWidgetGeometry = registry.PrepareLooseWidgetGeometry
    if type(drawWidgetSlots) ~= "function" or type(getCursorPosXSafe) ~= "function" then
        return false
    end
    local previousSlotGeometry = type(node) == "table" and node._slotGeometry or nil
    if type(node) == "table" and node._slotGeometry == nil and type(prepareLooseWidgetGeometry) == "function" then
        node._slotGeometry = prepareLooseWidgetGeometry(node.geometry)
    end
    local changed = drawWidgetSlots(imgui, node, slots, rowStart or getCursorPosXSafe(imgui)) == true
    if type(node) == "table" then
        node._slotGeometry = previousSlotGeometry
    end
    return changed
end

function public.alignSlotContent(imgui, slot, contentWidth)
    local registry = shared.fieldRegistry or {}
    local alignSlotContent = registry.AlignSlotContent
    if type(alignSlotContent) ~= "function" then
        return
    end
    alignSlotContent(imgui, slot, contentWidth)
end

function public.buildIndexedHiddenSlotGeometry(items, slotPrefix, opts)
    opts = opts or {}
    if type(slotPrefix) ~= "string" or slotPrefix == "" then
        if type(libWarn) == "function" then
            libWarn("buildIndexedHiddenSlotGeometry: slotPrefix must be a non-empty string")
        end
        return { slots = {} }, 0
    end

    local itemCount
    if type(items) == "number" then
        if items < 0 or math.floor(items) ~= items then
            if type(libWarn) == "function" then
                libWarn("buildIndexedHiddenSlotGeometry: numeric items must be a non-negative integer")
            end
            return { slots = {} }, 0
        end
        itemCount = items
    elseif type(items) == "table" then
        itemCount = #items
    else
        if type(libWarn) == "function" then
            libWarn("buildIndexedHiddenSlotGeometry: items must be a list or non-negative integer count")
        end
        return { slots = {} }, 0
    end

    local isHidden = type(opts.isHidden) == "function" and opts.isHidden or nil
    local resolveLine = type(opts.line) == "function" and opts.line or nil
    local slots = {}
    local visibleCount = 0

    for index = 1, itemCount do
        local item = type(items) == "table" and items[index] or nil
        -- This is the next visible slot index this item would receive if it is
        -- not hidden, not the count of already-confirmed visible items.
        local nextVisibleIndex = visibleCount + 1
        local hidden = isHidden ~= nil
            and isHidden(item, index, nextVisibleIndex) == true
            or type(item) == "table" and item.hidden == true
            or false

        local slot = {
            name = slotPrefix .. tostring(index),
            hidden = hidden or nil,
        }
        if not hidden then
            visibleCount = nextVisibleIndex
        end
        if resolveLine ~= nil then
            local line = resolveLine(item, index, hidden and nil or nextVisibleIndex, hidden)
            if type(line) == "number" then
                slot.line = line
            end
        end
        slots[index] = slot
    end

    return { slots = slots }, visibleCount
end

public.StorageTypes = shared.StorageTypes
public.WidgetTypes = shared.WidgetTypes
public.WidgetHelpers = shared.WidgetHelpers
public.LayoutTypes = shared.LayoutTypes
public.validateRegistries()
