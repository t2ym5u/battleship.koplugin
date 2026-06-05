local UndoStack  = require("undo_stack")
local grid_utils = require("grid_utils")

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

-- Reveal percentages per difficulty
local REVEAL = { easy = 0.25, medium = 0.15, hard = 0.05 }

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
    obj:generate()
    return obj
end

function BattleshipBoard:generate(diff)
    self.difficulty = diff or self.difficulty
    local n = self.n
    local sol = generateFleet(n)
    if not sol then
        sol = emptyBoolGrid(n, n)
        -- minimal fallback: one submarine
        sol[1][1] = true
    end
    self.solution    = sol
    self.marks       = emptyGrid(n, n, MARK_UNKNOWN)
    self.given       = emptyBoolGrid(n, n)
    self.wrong_cells = emptyBoolGrid(n, n)
    self.won         = false
    self.undo:clear()

    -- Row/col clues
    self.row_clues = {}
    self.col_clues = {}
    for r = 1, n do
        local cnt = 0
        for c = 1, n do if sol[r][c] then cnt = cnt + 1 end end
        self.row_clues[r] = cnt
    end
    for c = 1, n do
        local cnt = 0
        for r = 1, n do if sol[r][c] then cnt = cnt + 1 end end
        self.col_clues[c] = cnt
    end

    -- Reveal hints based on difficulty
    local reveal_prob = REVEAL[self.difficulty] or 0.15
    for r = 1, n do
        for c = 1, n do
            if math.random() < reveal_prob then
                self.given[r][c]  = true
                self.marks[r][c]  = sol[r][c] and MARK_SHIP or MARK_WATER
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

function BattleshipBoard:_checkWin()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            local sol_mark = self.solution[r][c] and MARK_SHIP or MARK_WATER
            if self.marks[r][c] ~= sol_mark and self.marks[r][c] ~= MARK_UNKNOWN then
                -- might be wrong but could still be valid without unknown cells
            end
            if self.marks[r][c] == MARK_UNKNOWN then
                self.won = false; return
            end
        end
    end
    -- All cells filled — check if correct
    for r = 1, n do
        for c = 1, n do
            local sol_mark = self.solution[r][c] and MARK_SHIP or MARK_WATER
            if self.marks[r][c] ~= sol_mark then
                self.won = false; return
            end
        end
    end
    self.won = true
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

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
