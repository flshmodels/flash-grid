local Rules = {}

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Rules.snap(value, step)
    local rounded = math.floor(math.abs(value) / step + 0.5) * step
    return if value < 0 then -rounded else rounded
end

function Rules.plan(rows, options)
    assert(#rows > 0 and #rows <= 500, "Select between 1 and 500 parts.")
    assert(finite(options.step) and options.step >= 0.01 and options.step <= 1024, "Grid size must be between 0.01 and 1024 studs.")
    assert(type(options.axes) == "string" and options.axes:match("^[XYZ]+$") and #options.axes <= 3, "Axes must contain X, Y or Z, such as XZ.")
    local plan = {}
    for _, row in ipairs(rows) do
        local after = {}
        local changed = false
        for _, axis in ipairs({ "X", "Y", "Z" }) do
            local value = row.position[axis]
            assert(finite(value) and math.abs(value) <= 1000000, "Part coordinates must be finite and within one million studs of the origin.")
            after[axis] = if options.axes:find(axis, 1, true) then Rules.snap(value, options.step) else value
            changed = changed or after[axis] ~= value
        end
        if changed then table.insert(plan, { before = row, after = after }) end
    end
    return plan
end

return Rules
