local Rules = require(script.Parent.Rules)
local Adapter = {}

local function eligible(part)
    if not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then
        return false, "Select BaseParts inside Workspace, not Models or folders."
    end
    if not part.Anchored or part.Locked then return false, "Parts must be anchored and unlocked." end
    for _, connected in ipairs(part:GetConnectedParts(true)) do
        if connected ~= part then return false, "Connected assemblies are not supported. Select loose, anchored parts." end
    end
    return true
end

function Adapter.controls(panel, changed)
    panel.label("Snap part centers to a world grid. Rotation and size stay unchanged. Models and connected assemblies are refused.")
    local step = panel.field("Grid size (studs)", "1")
    local axes = panel.field("Axes (X, Y, Z or a combination)", "XZ")
    step:GetPropertyChangedSignal("Text"):Connect(changed)
    axes:GetPropertyChangedSignal("Text"):Connect(changed)
    return function() return { step = tonumber(step.Text), axes = axes.Text } end
end

function Adapter.plan(selection, options)
    assert(#selection <= 500, "Select no more than 500 parts.")
    local rows, seen = {}, {}
    for _, part in ipairs(selection) do
        if not seen[part] then
            local ok, reason = eligible(part)
            assert(ok, reason)
            seen[part] = true
            table.insert(rows, {
                target = part, parent = part.Parent, cframe = part.CFrame,
                position = { X = part.Position.X, Y = part.Position.Y, Z = part.Position.Z },
            })
        end
    end
    local plan = Rules.plan(rows, options)
    for _, entry in ipairs(plan) do
        local old, new = entry.before.position, entry.after
        entry.label = string.format("%s\n(%.4f, %.4f, %.4f) -> (%.4f, %.4f, %.4f)", entry.before.target:GetFullName(), old.X, old.Y, old.Z, new.X, new.Y, new.Z)
    end
    return plan
end

function Adapter.validate(plan)
    for _, entry in ipairs(plan) do
        local before = entry.before
        local ok, reason = eligible(before.target)
        if not ok then return false, reason end
        if before.target.Parent ~= before.parent or before.target.CFrame ~= before.cframe then
            return false, "A part moved or changed parent. Preview again."
        end
    end
    return true
end

function Adapter.write(entry)
    local before, after = entry.before, entry.after
    local destination = Vector3.new(after.X, after.Y, after.Z)
    before.target.CFrame = before.cframe + (destination - before.cframe.Position)
end

return Adapter
