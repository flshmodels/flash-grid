local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Rules = require("../src/Rules")
local Transaction = require("../src/Transaction")
local count = 0
local function test(name, callback)
    local ok, err = pcall(callback)
    assert(ok, name .. ": " .. tostring(err))
    count += 1
    print("PASS " .. name)
end
local function rejects(callback)
    assert(not pcall(callback), "expected an error")
end
for _, name in ipairs(fs.readDir("src")) do
    if name:match("%.luau$") then luau.compile(fs.readFile("src/" .. name)) end
end

test("transaction commits one batch", function()
    local writes, commits = 0, 0
    local ok = Transaction.apply({ {}, {} }, {
        validate = function() return true end,
        write = function() writes += 1 end,
    }, {
        begin = function() return "recording" end,
        finish = function(id, commit) assert(id == "recording" and commit) commits += 1 end,
    })
    assert(ok and writes == 2 and commits == 1)
end)
test("empty, stale and uncheckable plans never begin a recording", function()
    local function forbidden() error("must not be called") end
    for _, mode in ipairs({ "empty", "stale", "throw" }) do
        local began = false
        local ok = Transaction.apply(if mode == "empty" then {} else { {} }, {
            validate = function() if mode == "throw" then error("deleted") end return false, "stale" end,
            write = forbidden,
        }, { begin = function() began = true return "id" end, finish = forbidden })
        assert(not ok and not began)
    end
end)
test("refused or failing undo recordings do not edit objects", function()
    for _, mode in ipairs({ "refuse", "throw" }) do
        local writes = 0
        local ok = Transaction.apply({ {} }, { validate = function() return true end, write = function() writes += 1 end }, {
            begin = function() if mode == "throw" then error("busy") end return nil end,
            finish = function() error("must not finish") end,
        })
        assert(not ok and writes == 0)
    end
end)
test("write failures cancel and restore the fake scene", function()
    local state, snapshot, cancelled = 0, 0, false
    local ok = Transaction.apply({ {}, {} }, {
        validate = function() return true end,
        write = function() state += 1 if state == 2 then error("locked") end end,
    }, {
        begin = function() snapshot = state return "id" end,
        finish = function(_, commit) assert(not commit) state = snapshot cancelled = true end,
    })
    assert(not ok and cancelled and state == 0)
end)
test("failed commits attempt cancellation", function()
    local cancelled = false
    local ok = Transaction.apply({ {} }, { validate = function() return true end, write = function() end }, {
        begin = function() return "id" end,
        finish = function(_, commit) if commit then error("commit failed") end cancelled = true end,
    })
    assert(not ok and cancelled)
end)
test("failed cancellation is reported", function()
    local ok, message = Transaction.apply({ {} }, { validate = function() return true end, write = function() error("write failed") end }, {
        begin = function() return "id" end,
        finish = function() error("cancel failed") end,
    })
    assert(not ok and message:find("could not cancel", 1, true))
end)

local gameRoot = { Name = "Game" }
local world = { Name = "Workspace", Parent = gameRoot, children = {} }
function world:GetChildren() return self.children end
function world:IsDescendantOf(ancestor) return ancestor == gameRoot end
local function object(name, parent, class)
    local node = { Name = name, Parent = parent, children = {}, attributes = {}, Anchored = true, Locked = false, connected = {} }
    node.CFrame = roblox.CFrame.new(0.4, -0.5, 3.6) * roblox.CFrame.Angles(0, 0.4, 0)
    setmetatable(node, { __index = function(self, key) if key == "Position" then return self.CFrame.Position end return nil end })
    function node:IsA(candidate) return candidate == "BasePart" and class == "BasePart" end
    function node:IsDescendantOf(ancestor)
        local cursor = self.Parent
        while cursor do if cursor == ancestor then return true end cursor = cursor.Parent end
        return false
    end
    function node:GetFullName()
        local names, cursor = {}, self
        while cursor and cursor ~= gameRoot do table.insert(names, 1, cursor.Name) cursor = cursor.Parent end
        return table.concat(names, ".")
    end
    function node:GetChildren() return self.children end
    function node:GetConnectedParts() return self.connected end
    function node:GetAttribute(name) return self.attributes[name] end
    function node:SetAttribute(name, value) self.attributes[name] = value end
    if parent and parent.children then table.insert(parent.children, node) end
    return node
end
local Adapter = luau.load(fs.readFile("src/Adapter.luau"), { environment = {
    require = function() return Rules end,
    script = { Parent = { Rules = {} } },
    game = gameRoot, workspace = world, Vector3 = roblox.Vector3,
} })()

test("negative halves round away from zero", function()
    assert(Rules.snap(-0.5, 1) == -1 and Rules.snap(0.5, 1) == 1)
    assert(math.abs(Rules.snap(-0.125, 0.25) + 0.25) < 1e-8)
end)
test("only requested axes change and exact grid points are omitted", function()
    local row = { position = { X = 0.4, Y = -0.5, Z = 3.6 } }
    local plan = Rules.plan({ row }, { step = 1, axes = "XZ" })
    assert(plan[1].after.X == 0 and plan[1].after.Y == -0.5 and plan[1].after.Z == 4)
    assert(#Rules.plan({ { position = { X = 1, Y = 2, Z = 3 } } }, { step = 1, axes = "XYZ" }) == 0)
end)
test("invalid steps, axes and coordinates are refused", function()
    for _, step in ipairs({ 0, -1, math.huge, 0.001, 2048 }) do
        rejects(function() Rules.plan({ { position = { X = 0, Y = 0, Z = 0 } } }, { step = step, axes = "XYZ" }) end)
    end
    rejects(function() Rules.plan({}, { step = 1, axes = "XYZ" }) end)
    rejects(function() Rules.plan({ { position = { X = 0/0, Y = 0, Z = 0 } } }, { step = 1, axes = "X" }) end)
    rejects(function() Rules.plan({ { position = { X = 0, Y = 0, Z = 0 } } }, { step = 1, axes = "Q" }) end)
end)
test("grid adapter preserves rotation and deduplicates selection", function()
    local part = object("Part", world, "BasePart")
    local rotation = part.CFrame.Rotation
    local plan = Adapter.plan({ part, part }, { step = 1, axes = "XYZ" })
    assert(#plan == 1 and Adapter.validate(plan))
    Adapter.write(plan[1])
    assert(part.CFrame.Position == roblox.Vector3.new(0, -1, 4))
    assert(part.CFrame.Rotation == rotation)
end)
test("moving or locking a preview target makes it stale", function()
    local part = object("Part", world, "BasePart")
    local plan = Adapter.plan({ part }, { step = 1, axes = "XYZ" })
    part.CFrame = roblox.CFrame.new(9, 9, 9)
    assert(not Adapter.validate(plan))
    part.CFrame = plan[1].before.cframe
    part.Locked = true
    assert(not Adapter.validate(plan))
end)
test("models, unanchored parts and connected assemblies are refused", function()
    local model = object("Model", world, "Model")
    rejects(function() Adapter.plan({ model }, { step = 1, axes = "XYZ" }) end)
    local part = object("Part", world, "BasePart")
    part.Anchored = false
    rejects(function() Adapter.plan({ part }, { step = 1, axes = "XYZ" }) end)
    part.Anchored = true
    part.connected = { object("Other", world, "BasePart") }
    rejects(function() Adapter.plan({ part }, { step = 1, axes = "XYZ" }) end)
end)

print(string.format("%d checks passed", count))
