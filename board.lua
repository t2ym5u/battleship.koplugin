local UndoStack  = require("undo_stack")
local grid_utils = require("grid_utils")
local Hint      = require("hint")

-- solver.lua sits next to this file; loaded by path so no other plugin's
-- module of the same name can stand in for it.
local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local Solver = assert(loadfile(_dir .. "solver.lua"))()

local shuffle    = grid_utils.shuffle
local emptyGrid  = grid_utils.emptyGrid
local emptyBoolGrid = grid_utils.emptyBoolGrid

-- Player cell marks
local MARK_UNKNOWN = 0
local MARK_WATER   = 1
local MARK_SHIP    = 2

-- Standard fleet: {length, count}
local FLEET = { {4,1}, {3,2}, {2,3}, {1,4} }

local SIZES     = { 8, 10 }
local DEFAULT_N = 10
local DEFAULT_DIFF = "medium"

-- Levels. tier: the hardest deductions the puzzle may need (see
-- solver.lua: 0 basic, 1 fleet counting, 2 where the ships can still go).
-- Easy keeps every reveal it took to get there; Medium and Hard drop the
-- ones the solver can do without. A level retries new fleets (a bounded
-- number of times) until its puzzle really needs its kind of deduction,
-- and otherwise keeps the hardest one it built.
local LEVELS = {
    easy   = { tier = 0, ship_bias = 0.6, minimize = false, attempts = 1,
               accept = function() return true end },
    medium = { tier = 1, ship_bias = 0.5, minimize = true, attempts = 6,
               accept = function(s) return s[1] >= 1 end },
    hard   = { tier = 2, ship_bias = 0.5, minimize = true, attempts = 6,
               accept = function(s) return s[2] >= 1 end },
}

-- ---------------------------------------------------------------------------
-- Generator helpers
-- ---------------------------------------------------------------------------

local function inBounds(r, c, n)
    return r >= 1 and r <= n and c >= 1 and c <= n
end

local function canPlace(grid, n, r, c, length, horiz)
    -- Check all cells + 1-cell border
    for i = 0, length - 1 do
        local pr = r + (horiz and 0 or i)
        local pc = c + (horiz and i or 0)
        if not inBounds(pr, pc, n) then return false end
        if grid[pr][pc] then return false end
        -- check 8-neighbors
        for dr = -1, 1 do
            for dc = -1, 1 do
                local nr, nc = pr + dr, pc + dc
                if inBounds(nr, nc, n) and grid[nr][nc] then return false end
            end
        end
    end
    return true
end

local function placeShip(grid, r, c, length, horiz)
    for i = 0, length - 1 do
        local pr = r + (horiz and 0 or i)
        local pc = c + (horiz and i or 0)
        grid[pr][pc] = true
    end
end

local function generateFleet(n)
    for _ = 1, 50 do
        local grid = emptyBoolGrid(n, n)
        local ok = true
        for _, spec in ipairs(FLEET) do
            local length, count = spec[1], spec[2]
            for _ = 1, count do
                local placed = false
                local positions = {}
                for r = 1, n do
                    for c = 1, n do
                        for _, h in ipairs({true, false}) do
                            if canPlace(grid, n, r, c, length, h) then
                                positions[#positions + 1] = {r, c, h}
                            end
                        end
                    end
                end
                shuffle(positions)
                for _, pos in ipairs(positions) do
                    if canPlace(grid, n, pos[1], pos[2], length, pos[3]) then
                        placeShip(grid, pos[1], pos[2], length, pos[3])
                        placed = true
                        break
                    end
                end
                if not placed then ok = false; break end
            end
            if not ok then break end
        end
        if ok then return grid end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- BattleshipBoard
-- ---------------------------------------------------------------------------

local BattleshipBoard = {}
BattleshipBoard.__index = BattleshipBoard

function BattleshipBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        n          = opts.n          or DEFAULT_N,
        difficulty = opts.difficulty or DEFAULT_DIFF,
        solution   = nil,
        marks      = nil,
        given      = nil,    -- pre-revealed cells
        row_clues  = nil,
        col_clues  = nil,
        wrong_cells= nil,
        won        = false,
        undo       = UndoStack:new{ max_size = 500 },
    }, self)
    -- opts.empty: the caller loads a save or generates itself, so don't
    -- build a puzzle that would be thrown away.
    if not opts.empty then obj:generate() end
    return obj
end

-- Clue counts of a solution grid.
local function lineClues(sol, n)
    local rows, cols = {}, {}
    for r = 1, n do
        local cnt = 0
        for c = 1, n do if sol[r][c] then cnt = cnt + 1 end end
        rows[r] = cnt
    end
    for c = 1, n do
        local cnt = 0
        for r = 1, n do if sol[r][c] then cnt = cnt + 1 end end
        cols[c] = cnt
    end
    return rows, cols
end

-- Builds one puzzle for a fleet: reveals cells, chosen among those the
-- solver is stuck on, until the solver (limited to the level's deductions)
-- fills the whole grid -- so the puzzle has one solution and needs no
-- guessing. Medium and Hard then drop every reveal the solver can do
-- without. Returns givens (flat: 0 none, 1 water, 2 ship) and solver stats.
local function buildPuzzle(sol, n, rows, cols, level)
    local NN = n * n
    local truth, givens = {}, {}
    for r = 1, n do
        for c = 1, n do
            local i = (r - 1) * n + c
            truth[i] = sol[r][c] and Solver.SHIP or Solver.WATER
            givens[i] = Solver.UNK
        end
    end
    local tier = level.tier
    local ok, st, stats = Solver.solve(n, rows, cols, givens, tier)
    while not ok do
        -- Stuck: reveal one of the cells the solver could not decide.
        local ships, waters = {}, {}
        for i = 1, NN do
            if st[i] == Solver.UNK then
                if truth[i] == Solver.SHIP then ships[#ships + 1] = i else waters[#waters + 1] = i end
            end
        end
        local pick
        assert(#ships + #waters > 0, "battleship: solver stuck on a full grid")
        if #ships > 0 and (#waters == 0 or math.random() < level.ship_bias) then
            pick = ships[math.random(#ships)]
        else
            pick = waters[math.random(#waters)]
        end
        givens[pick] = truth[pick]
        -- The deductions only grow with more reveals, so carrying on from
        -- where the solver stopped reaches the same end as starting over.
        st[pick] = truth[pick]
        ok, st = Solver.solve(n, rows, cols, st, tier)
    end
    if level.minimize then
        local list = {}
        for i = 1, NN do if givens[i] ~= Solver.UNK then list[#list + 1] = i end end
        shuffle(list)
        for _, i in ipairs(list) do
            givens[i] = Solver.UNK
            if not Solver.solve(n, rows, cols, givens, tier) then givens[i] = truth[i] end
        end
    end
    ok, st, stats = Solver.solve(n, rows, cols, givens, tier)
    assert(ok, "battleship: unverified puzzle")
    local count = 0
    for i = 1, NN do if givens[i] ~= Solver.UNK then count = count + 1 end end
    stats.reveals = count
    return givens, stats
end

-- How hard a built puzzle is, for the level that asked for it (higher is
-- closer to what the level wants).
local function fitness(stats, level)
    if level.tier == 0 then return 0 end
    return stats[level.tier] * 100 - stats.reveals
end

function BattleshipBoard:generate(diff, on_progress)
    self.difficulty = diff or self.difficulty
    local n = self.n
    local level = LEVELS[self.difficulty] or LEVELS[DEFAULT_DIFF]
    local best
    for attempt = 1, level.attempts do
        if on_progress then on_progress((attempt - 1) / level.attempts) end
        local sol = generateFleet(n)
        if sol then
            local rows, cols = lineClues(sol, n)
            local givens, stats = buildPuzzle(sol, n, rows, cols, level)
            local f = fitness(stats, level)
            if not best or f > best.f then
                best = { sol = sol, rows = rows, cols = cols, givens = givens, stats = stats, f = f }
            end
            if level.accept(stats, n) then break end
        end
    end
    if not best then
        -- generateFleet never fails on 8x8/10x10; this only keeps the
        -- board usable: a lone submarine, every other cell given.
        local sol = emptyBoolGrid(n, n)
        sol[1][1] = true
        local rows, cols = lineClues(sol, n)
        local givens = {}
        for i = 1, n * n do givens[i] = i == 1 and Solver.UNK or Solver.WATER end
        best = { sol = sol, rows = rows, cols = cols, givens = givens, stats = { [0] = 0, [1] = 0, [2] = 0, reveals = n * n - 1 } }
    end
    if on_progress then on_progress(1) end

    self.solution    = best.sol
    self.row_clues   = best.rows
    self.col_clues   = best.cols
    self.stats       = best.stats
    self.marks       = emptyGrid(n, n, MARK_UNKNOWN)
    self.given       = emptyBoolGrid(n, n)
    self.wrong_cells = emptyBoolGrid(n, n)
    self.won         = false
    self.undo:clear()
    for r = 1, n do
        for c = 1, n do
            local g = best.givens[(r - 1) * n + c]
            if g ~= Solver.UNK then
                self.given[r][c] = true
                self.marks[r][c] = g == Solver.SHIP and MARK_SHIP or MARK_WATER
            end
        end
    end
end

function BattleshipBoard:setMark(r, c, mark)
    if self.given[r][c] then return false end
    if self.won then return false end
    local old = self.marks[r][c]
    if old == mark then mark = MARK_UNKNOWN end
    self.undo:push{ r = r, c = c, old = old }
    self.marks[r][c]        = mark
    self.wrong_cells[r][c]  = false
    self:_checkWin()
    return true
end

function BattleshipBoard:cycleCell(r, c)
    if self.given[r][c] then return false end
    local cur = self.marks[r][c]
    local next_mark
    if     cur == MARK_UNKNOWN then next_mark = MARK_SHIP
    elseif cur == MARK_SHIP    then next_mark = MARK_WATER
    else                            next_mark = MARK_UNKNOWN
    end
    return self:setMark(r, c, next_mark)
end

function BattleshipBoard:undoMove()
    local entry = self.undo:pop()
    if not entry then return false end
    self.marks[entry.r][entry.c]       = entry.old
    self.wrong_cells[entry.r][entry.c] = false
    self.won = false
    return true
end

function BattleshipBoard:check()
    local n = self.n
    self.wrong_cells = emptyBoolGrid(n, n)
    -- Check row counts
    for r = 1, n do
        local cnt = 0
        for c = 1, n do if self.marks[r][c] == MARK_SHIP then cnt = cnt + 1 end end
        if cnt ~= self.row_clues[r] then
            for c = 1, n do
                if self.marks[r][c] == MARK_SHIP then self.wrong_cells[r][c] = true end
            end
        end
    end
    -- Check col counts
    for c = 1, n do
        local cnt = 0
        for r = 1, n do if self.marks[r][c] == MARK_SHIP then cnt = cnt + 1 end end
        if cnt ~= self.col_clues[c] then
            for r = 1, n do
                if self.marks[r][c] == MARK_SHIP then self.wrong_cells[r][c] = true end
            end
        end
    end
end

function BattleshipBoard:reveal()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            self.marks[r][c] = self.solution[r][c] and MARK_SHIP or MARK_WATER
        end
    end
    self.won = true
end

-- True when `ship(r, c)` describes a grid that keeps every rule: the row
-- and column counts, ships straight and never touching (not even at a
-- corner), and exactly the standard fleet.
local function obeysRules(n, ship, row_clues, col_clues)
    for r = 1, n do
        local cnt = 0
        for c = 1, n do if ship(r, c) then cnt = cnt + 1 end end
        if cnt ~= (row_clues[r] or 0) then return false end
    end
    for c = 1, n do
        local cnt = 0
        for r = 1, n do if ship(r, c) then cnt = cnt + 1 end end
        if cnt ~= (col_clues[c] or 0) then return false end
    end
    local need = {}
    for _, spec in ipairs(FLEET) do need[spec[1]] = spec[2] end
    for r = 1, n do
        for c = 1, n do
            if ship(r, c) then
                -- Corners touching: never allowed.
                if (r < n and c > 1 and ship(r + 1, c - 1))
                    or (r < n and c < n and ship(r + 1, c + 1)) then
                    return false
                end
                local left = c > 1 and ship(r, c - 1)
                local up   = r > 1 and ship(r - 1, c)
                if not left and not up then
                    -- First cell of a ship: measure it.
                    local right = c < n and ship(r, c + 1)
                    local down  = r < n and ship(r + 1, c)
                    if right and down then return false end
                    local len = 1
                    if right then
                        while c + len <= n and ship(r, c + len) do len = len + 1 end
                    elseif down then
                        while r + len <= n and ship(r + len, c) do len = len + 1 end
                    end
                    if not need[len] or need[len] == 0 then return false end
                    need[len] = need[len] - 1
                elseif left and up then
                    return false
                end
            end
        end
    end
    for _, k in pairs(need) do if k ~= 0 then return false end end
    return true
end

-- Solved once every cell is marked and the ships keep the rules. Any such
-- grid counts, not only the stored solution (generated puzzles have just
-- one, but a game saved by an older version may have had more).
function BattleshipBoard:_checkWin()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            if self.marks[r][c] == MARK_UNKNOWN then
                self.won = false; return
            end
        end
    end
    local marks = self.marks
    self.won = obeysRules(n, function(r, c) return marks[r][c] == MARK_SHIP end,
        self.row_clues, self.col_clues)
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

-- _checkWin() refuses any cell left unknown, so water is as much a move as a
-- ship here and both get offered.
Hint.install(BattleshipBoard, {
    getUser     = function(b, r, c) return b.marks[r][c] end,
    getSolution = function(b, r, c) return b.solution[r][c] and MARK_SHIP or MARK_WATER end,
    isEmpty     = function(v) return v == MARK_UNKNOWN end,
    isGiven     = function(b, r, c) return b.given[r][c] == true end,
    setCell     = function(b, r, c, v) return b:setMark(r, c, v) end,
    blank       = MARK_UNKNOWN,
})

function BattleshipBoard:serialize()
    local n = self.n
    local sol_flat, marks_flat, given_flat = {}, {}, {}
    for r = 1, n do
        for c = 1, n do
            sol_flat[#sol_flat + 1]   = self.solution[r][c] and 1 or 0
            marks_flat[#marks_flat + 1] = self.marks[r][c]
            given_flat[#given_flat + 1] = self.given[r][c] and 1 or 0
        end
    end
    return {
        n          = n,
        difficulty = self.difficulty,
        solution   = sol_flat,
        marks      = marks_flat,
        given      = given_flat,
        row_clues  = self.row_clues,
        col_clues  = self.col_clues,
        won        = self.won,
    }
end

function BattleshipBoard:load(data)
    if type(data) ~= "table" or not data.solution then return false end
    local n = data.n or DEFAULT_N
    self.n          = n
    self.difficulty = data.difficulty or DEFAULT_DIFF
    self.solution   = emptyBoolGrid(n, n)
    self.marks      = emptyGrid(n, n, MARK_UNKNOWN)
    self.given      = emptyBoolGrid(n, n)
    self.wrong_cells= emptyBoolGrid(n, n)
    local idx = 1
    for r = 1, n do
        for c = 1, n do
            self.solution[r][c] = (data.solution[idx] or 0) == 1
            self.marks[r][c]    = data.marks[idx] or MARK_UNKNOWN
            self.given[r][c]    = (data.given[idx] or 0) == 1
            idx = idx + 1
        end
    end
    self.row_clues   = data.row_clues   or {}
    self.col_clues   = data.col_clues   or {}
    self.won         = data.won         or false
    self.undo:clear()
    return true
end

BattleshipBoard.MARK_UNKNOWN = MARK_UNKNOWN
BattleshipBoard.MARK_WATER   = MARK_WATER
BattleshipBoard.MARK_SHIP    = MARK_SHIP
BattleshipBoard.SIZES        = SIZES
BattleshipBoard.DEFAULT_N    = DEFAULT_N
BattleshipBoard.FLEET        = FLEET

return BattleshipBoard
