local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("BattleshipBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    describe("new / generate", function()
        it("creates a 10x10 board with the standard fleet placed", function()
            math.randomseed(42)
            local b = Board:new()
            assert.are.equal(10, b.n)
            local ship_cells = 0
            for r = 1, b.n do
                for c = 1, b.n do
                    if b.solution[r][c] then ship_cells = ship_cells + 1 end
                end
            end
            -- Standard fleet: 4+3+3+2+2+2+1+1+1+1 = 20 cells
            assert.are.equal(20, ship_cells)
        end)

        it("row/col clues match the actual ship counts", function()
            math.randomseed(7)
            local b = Board:new()
            for r = 1, b.n do
                local cnt = 0
                for c = 1, b.n do if b.solution[r][c] then cnt = cnt + 1 end end
                assert.are.equal(cnt, b.row_clues[r])
            end
            for c = 1, b.n do
                local cnt = 0
                for r = 1, b.n do if b.solution[r][c] then cnt = cnt + 1 end end
                assert.are.equal(cnt, b.col_clues[c])
            end
        end)

        it("ships form exactly the standard fleet as orthogonally-connected runs", function()
            math.randomseed(3)
            local b = Board:new()
            local n = b.n
            local visited = {}
            for r = 1, n do visited[r] = {} end
            local sizes = {}
            for r = 1, n do
                for c = 1, n do
                    if b.solution[r][c] and not visited[r][c] then
                        local stack, size = { { r, c } }, 0
                        visited[r][c] = true
                        while #stack > 0 do
                            local cell = table.remove(stack)
                            size = size + 1
                            for _, d in ipairs({ {1,0}, {-1,0}, {0,1}, {0,-1} }) do
                                local nr, nc = cell[1] + d[1], cell[2] + d[2]
                                if nr >= 1 and nr <= n and nc >= 1 and nc <= n
                                    and b.solution[nr][nc] and not visited[nr][nc] then
                                    visited[nr][nc] = true
                                    stack[#stack + 1] = { nr, nc }
                                end
                            end
                        end
                        sizes[#sizes + 1] = size
                    end
                end
            end
            table.sort(sizes)
            -- FLEET = { {4,1}, {3,2}, {2,3}, {1,4} } -> ten ships total
            assert.are.same({ 1, 1, 1, 1, 2, 2, 2, 3, 3, 4 }, sizes)
        end)
    end)

    describe("cycleCell / setMark", function()
        it("cycles a free cell through unknown -> ship -> water -> unknown", function()
            math.randomseed(42)
            local b = Board:new()
            local r, c = 1, 1
            while b.given[r][c] do
                c = c + 1
                if c > b.n then c = 1; r = r + 1 end
            end
            assert.are.equal(Board.MARK_UNKNOWN, b.marks[r][c])
            b:cycleCell(r, c)
            assert.are.equal(Board.MARK_SHIP, b.marks[r][c])
            b:cycleCell(r, c)
            assert.are.equal(Board.MARK_WATER, b.marks[r][c])
            b:cycleCell(r, c)
            assert.are.equal(Board.MARK_UNKNOWN, b.marks[r][c])
        end)

        it("refuses to change a given (pre-revealed) cell", function()
            math.randomseed(42)
            local b = Board:new()
            local r, c
            for rr = 1, b.n do
                for cc = 1, b.n do
                    if b.given[rr][cc] then r, c = rr, cc; break end
                end
                if r then break end
            end
            assert.is_false(b:cycleCell(r, c))
        end)
    end)

    describe("undoMove", function()
        it("restores the previous mark", function()
            math.randomseed(42)
            local b = Board:new()
            local r, c = 1, 1
            while b.given[r][c] do
                c = c + 1
                if c > b.n then c = 1; r = r + 1 end
            end
            b:cycleCell(r, c)
            assert.is_true(b:undoMove())
            assert.are.equal(Board.MARK_UNKNOWN, b.marks[r][c])
        end)

        it("returns false when there is nothing to undo", function()
            math.randomseed(42)
            local b = Board:new()
            assert.is_false(b:undoMove())
        end)
    end)

    describe("reveal", function()
        it("fills every cell to match the solution and wins", function()
            math.randomseed(42)
            local b = Board:new()
            b:reveal()
            assert.is_true(b.won)
            for r = 1, b.n do
                for c = 1, b.n do
                    local expected = b.solution[r][c] and Board.MARK_SHIP or Board.MARK_WATER
                    assert.are.equal(expected, b.marks[r][c])
                end
            end
        end)
    end)

    describe("serialize / load", function()
        it("round-trips solution, marks and clues", function()
            math.randomseed(42)
            local b = Board:new()
            b:reveal()
            local data = b:serialize()

            local b2 = Board:new()
            assert.is_true(b2:load(data))
            assert.are.equal(b.n, b2.n)
            assert.is_true(b2.won)
            for r = 1, b.n do
                for c = 1, b.n do
                    assert.are.equal(b.solution[r][c], b2.solution[r][c])
                end
            end
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)

    describe("new{ empty = true }", function()
        it("builds no puzzle, and load fills it from a save", function()
            local saved = Board:new{ n = 8, difficulty = "hard" }:serialize()
            local b = Board:new{ n = 8, difficulty = "hard", empty = true }
            assert.is_nil(b.solution)
            assert.is_true(b:load(saved))
            assert.are.same(saved, b:serialize())
        end)
    end)

    describe("fleetFound", function()
        -- Builds a board from rows of "S" (ship), "~" (water), "." (unknown).
        local function boardFrom(rows)
            local b = Board:new{ n = #rows, empty = true }
            b.n = #rows
            b.marks = {}
            for r, line in ipairs(rows) do
                b.marks[r] = {}
                for c = 1, #line do
                    local ch = line:sub(c, c)
                    b.marks[r][c] = ch == "S" and Board.MARK_SHIP
                        or ch == "~" and Board.MARK_WATER or Board.MARK_UNKNOWN
                end
            end
            return b
        end

        it("counts only ships closed by water or the edge", function()
            local f = boardFrom{
                "SSSS~S",
                "~~~~~.",
                "S~SS~~",
                "~~~~~S",
                "SS.~~S",
                "~~~~~S",
            }:fleetFound()
            -- Row 1: battleship closed by the edge and water; the cell at
            -- (1,6) has an unknown below it, so it is not finished yet.
            assert.are.equal(1, f[4])
            -- (3,1) sub and (3,3)-(3,4) destroyer are closed; (5,1)-(5,2)
            -- is open on the right; (4,6)-(6,6) is a closed cruiser.
            assert.are.equal(1, f[1])
            assert.are.equal(1, f[2])
            assert.are.equal(1, f[3])
        end)

        it("never counts a bent or touching shape", function()
            local f = boardFrom{
                "SS~~",
                "S~~~",
                "~~~~",
                "~~~~",
            }:fleetFound()
            assert.are.same({ [1] = 0, [2] = 0, [3] = 0, [4] = 0 }, f)
        end)

        it("counts the whole fleet once the solution is revealed", function()
            math.randomseed(3)
            local b = Board:new{ n = 8 }
            b:reveal()
            local f = b:fleetFound()
            for _, spec in ipairs(Board.FLEET) do
                assert.are.equal(spec[2], f[spec[1]])
            end
        end)
    end)
end)
