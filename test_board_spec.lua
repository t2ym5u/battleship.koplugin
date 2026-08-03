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
end)
