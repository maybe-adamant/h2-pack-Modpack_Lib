local internal = AdamantModpackLib_Internal
local shared = internal.shared

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

public.StorageTypes = shared.StorageTypes
public.WidgetTypes = shared.WidgetTypes
public.LayoutTypes = shared.LayoutTypes
public.validateRegistries()
