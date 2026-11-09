local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local function gridFrom(rows)
    local g = {}
    for r, line in ipairs(rows) do
        g[r] = {}
        for c = 1, #line do g[r][c] = line:sub(c, c) == "#" end
    end
    return g
end

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
