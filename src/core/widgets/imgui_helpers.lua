local imguiHelpers = {}

-- The ReturnOfModding Lua binding exposes these flag values as raw integer
-- parameters, but does not consistently expose the C++ enum tables at runtime.
imguiHelpers.ImGuiComboFlags = {
    None = 0,
    NoPreview = 64,
}

imguiHelpers.ImGuiCol = {
    Text = 0,
}

return imguiHelpers
