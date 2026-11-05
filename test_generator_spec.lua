local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local SEEDS = 10
local SIZES = { 8, 10 }
local LEVELS = { "easy", "medium", "hard" }
local TIER = { easy = 0, medium = 1, hard = 2 }

-- Flat givens (0 unknown, 1 water, 2 ship) of a board, as the solver takes them.
local function givensOf(b, Solver)
    local g = {}
    for r = 1, b.n do
        for c = 1, b.n do
            local v = Solver.UNK
            if b.given[r][c] then v = b.solution[r][c] and Solver.SHIP or Solver.WATER end
            g[(r - 1) * b.n + c] = v
        end
    end
    return g
end

local function gridFrom(rows)
    local g = {}
    for r, line in ipairs(rows) do
        g[r] = {}
        for c = 1, #line do g[r][c] = line:sub(c, c) == "#" end
    end
    return g
end

describe("Battleship generator", function()
    local Board, Solver

    setup(function()
        Board = require("board")
        Solver = dofile(DIR .. "solver.lua")
    end)

    for _, n in ipairs(SIZES) do
        for _, d in ipairs(LEVELS) do
            it(("%dx%d %s: solved by logic alone, at the level's deductions"):format(n, n, d), function()
                for seed = 1, SEEDS do
                    math.randomseed(seed)
                    local b = Board:new{ n = n, difficulty = d }
                    local ok, st = Solver.solve(n, b.row_clues, b.col_clues, givensOf(b, Solver), TIER[d])
                    assert.is_true(ok, "seed " .. seed)
                    for r = 1, n do
                        for c = 1, n do
                            local want = b.solution[r][c] and Solver.SHIP or Solver.WATER
                            assert.are.equal(want, st[(r - 1) * n + c])
                        end
                    end
                    -- The level is what it says: Medium needs fleet counting,
                    -- Hard needs placing the ships, Easy only the basics.
                    if TIER[d] >= 1 then
                        local easier = Solver.solve(n, b.row_clues, b.col_clues, givensOf(b, Solver), TIER[d] - 1)
                        assert.is_false(easier, "seed " .. seed .. " is not harder than the level below")
                    end
                end
            end)
        end

        it(("%dx%d: Easy reveals more than Medium, Medium at least as much as Hard"):format(n, n), function()
            local total = {}
            for _, d in ipairs(LEVELS) do
                total[d] = 0
                for seed = 1, SEEDS do
                    math.randomseed(seed)
                    total[d] = total[d] + Board:new{ n = n, difficulty = d }.stats.reveals
                end
            end
            assert.is_true(total.easy > total.medium)
            assert.is_true(total.medium >= total.hard)
        end)
    end

    it("the same seed builds the same puzzle", function()
        for _, d in ipairs(LEVELS) do
            math.randomseed(1234)
            local a = Board:new{ n = 10, difficulty = d }:serialize()
            math.randomseed(1234)
            local b = Board:new{ n = 10, difficulty = d }:serialize()
            assert.are.same(a, b)
        end
    end)

    it("builds a puzzle quickly (generous bound)", function()
        local worst = 0
        for _, n in ipairs(SIZES) do
            for seed = 1, SEEDS do
                math.randomseed(seed)
                local t = os.clock()
                Board:new{ n = n, difficulty = "hard" }
                worst = math.max(worst, os.clock() - t)
            end
        end
        assert.is_true(worst < 1.0, ("worst hard generation %.3f s"):format(worst))
    end)

    it("the solver never fills a cell against the solution", function()
        -- Starting from no reveal at all, whatever it deduces must be right.
        for seed = 1, 20 do
            math.randomseed(seed)
            local b = Board:new{ n = 10, difficulty = "easy" }
            local empty = {}
            for i = 1, 100 do empty[i] = Solver.UNK end
            local _, st, stats = Solver.solve(10, b.row_clues, b.col_clues, empty, 2)
            assert.is_false(stats.bad)
            for r = 1, 10 do
                for c = 1, 10 do
                    local v = st[(r - 1) * 10 + c]
                    if v ~= Solver.UNK then
                        assert.are.equal(b.solution[r][c] and Solver.SHIP or Solver.WATER, v)
                    end
                end
            end
        end
    end)
end)

describe("Battleship win check and old saves", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    -- These clues, with nothing revealed (an old version could ship that),
    -- have three solutions; the stored one is SOL, ALT is another.
    local SOL = {
        "#.#.....",
        "........",
        "####.#.#",
        ".....#.#",
        "##.#.#..",
        "........",
        "###.##..",
        ".......#",
    }
    local ALT = {
        ".#..#...",
        "........",
        "####.#.#",
        ".....#.#",
        "###..#..",
        "........",
        "#.##.#.#",
        "#.......",
    }

    -- A save as 1.4.x wrote it (same fields, no reveal at all).
    local function oldSave()
        local sol = gridFrom(SOL)
        local flat, marks, given = {}, {}, {}
        local rows, cols = {}, {}
        for i = 1, 8 do rows[i] = 0; cols[i] = 0 end
        for r = 1, 8 do
            for c = 1, 8 do
                flat[#flat + 1] = sol[r][c] and 1 or 0
                marks[#marks + 1] = 0
                given[#given + 1] = 0
                if sol[r][c] then rows[r] = rows[r] + 1; cols[c] = cols[c] + 1 end
            end
        end
        return { n = 8, difficulty = "hard", solution = flat, marks = marks, given = given,
                 row_clues = rows, col_clues = cols, won = false }
    end

    local function fill(b, rows)
        local g = gridFrom(rows)
        for r = 1, 8 do
            for c = 1, 8 do
                b:setMark(r, c, g[r][c] and Board.MARK_SHIP or Board.MARK_WATER)
            end
        end
    end

    it("loads a save from an older version", function()
        local b = Board:new{ empty = true }
        assert.is_true(b:load(oldSave()))
        assert.are.equal(8, b.n)
        assert.are.equal("hard", b.difficulty)
        assert.is_false(b.won)
    end)

    it("accepts the stored solution", function()
        local b = Board:new{ empty = true }
        b:load(oldSave())
        fill(b, SOL)
        assert.is_true(b.won)
    end)

    it("accepts another grid that keeps every rule", function()
        local b = Board:new{ empty = true }
        b:load(oldSave())
        fill(b, ALT)
        assert.is_true(b.won)
    end)

    -- A save whose stored "solution" is `rows` itself, clues to match: the
    -- win check must still judge the grid by the rules.
    local function saveOf(rows)
        local data = oldSave()
        local g = gridFrom(rows)
        for i = 1, 8 do data.row_clues[i] = 0; data.col_clues[i] = 0 end
        for r = 1, 8 do
            for c = 1, 8 do
                data.solution[(r - 1) * 8 + c] = g[r][c] and 1 or 0
                if g[r][c] then
                    data.row_clues[r] = data.row_clues[r] + 1
                    data.col_clues[c] = data.col_clues[c] + 1
                end
            end
        end
        return data
    end

    it("refuses a grid that matches the counts but not the fleet", function()
        -- Two submarines of SOL's top row glued into one more destroyer.
        local rows = {}
        for i, line in ipairs(SOL) do rows[i] = line end
        rows[1] = "##......"
        local b = Board:new{ empty = true }
        b:load(saveOf(rows))
        fill(b, rows)
        assert.is_false(b.won)
    end)

    it("refuses ships touching at a corner", function()
        local rows = {}
        for i, line in ipairs(SOL) do rows[i] = line end
        rows[8] = "......#." -- (8,7) touches the destroyer at (7,6)
        local b = Board:new{ empty = true }
        b:load(saveOf(rows))
        fill(b, rows)
        assert.is_false(b.won)
    end)

    it("refuses a bent ship", function()
        local rows = {}
        for i, line in ipairs(SOL) do rows[i] = line end
        rows[6] = "#......." -- (5,1),(5,2),(6,1): an L, not a straight ship
        local b = Board:new{ empty = true }
        b:load(saveOf(rows))
        fill(b, rows)
        assert.is_false(b.won)
    end)
end)
