-- Difficulty guarantees: each level is solved by logic alone at its own
-- deductions tier and needs that tier, the levels are ordered, and the
-- generator is deterministic and quick.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local SEEDS = 10
local SIZES = { 8, 10 }
local LEVELS = { "easy", "medium", "hard" }
local TIER = { easy = 0, medium = 1, hard = 2 }

-- Runs fn with os.clock/os.time wrapped; returns how often they were read.
local function clockReads(fn)
    local clock, time = os.clock, os.time
    local reads = 0
    os.clock = function() reads = reads + 1; return clock() end
    os.time = function(...) reads = reads + 1; return time(...) end
    local ok, err = pcall(fn)
    os.clock, os.time = clock, time
    assert(ok, err)
    return reads
end

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

describe("Battleship difficulty", function()
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

    it("generation never reads the clock", function()
        for _, d in ipairs(LEVELS) do
            local reads = clockReads(function()
                math.randomseed(7)
                Board:new{ n = 10, difficulty = d }
            end)
            assert.are.equal(0, reads, d)
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
