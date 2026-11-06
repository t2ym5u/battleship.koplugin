local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer     = require("ffi/blitbuffer")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")
local UIManager      = require("ui/uimanager")

local gwb      = lrequire("common/grid_widget_base")
local drawLine = gwb.drawLine

local BattleshipBoard = lrequire("board")

local C_BG      = Blitbuffer.COLOR_WHITE
local C_FG      = Blitbuffer.COLOR_BLACK
local C_GRID    = Blitbuffer.COLOR_GRAY_9
local C_SHIP    = Blitbuffer.COLOR_GRAY_4
local C_WATER   = Blitbuffer.COLOR_GRAY_E
local C_GIVEN   = Blitbuffer.COLOR_GRAY_2
local C_WRONG   = Blitbuffer.COLOR_GRAY_2
local C_UNKNOWN = Blitbuffer.COLOR_WHITE

-- Binary-search the largest font size whose rendered ink box for `sample`
-- fits within (max_w, max_h). A fixed size-to-cell ratio isn't safe:
-- Font:getFace scales the size by screen DPI, so `cell * 0.5` can render
-- taller than the cell itself on high-DPI screens.
local function bsearchFont(font_name, lo, hi, max_w, max_h, sample)
    local best = lo
    while lo <= hi do
        local mid  = math.floor((lo + hi) / 2)
        local face = Font:getFace(font_name, mid)
        local m    = RenderText:sizeUtf8Text(0, math.huge, face, sample, true, false)
        if m.x <= max_w and (m.y_top + m.y_bottom) <= max_h then
            best = mid
            lo   = mid + 1
        else
            hi   = mid - 1
        end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- BattleshipBoardWidget
-- ---------------------------------------------------------------------------

local BattleshipBoardWidget = InputContainer:extend{
    board      = nil,
    max_width  = 0,
    max_height = 0,
    cellTapCallback  = nil,
    cellHoldCallback = nil,
}

function BattleshipBoardWidget:init()
    local board = self.board
    local n     = board.n

    local cell = math.floor(math.min(self.max_width / (n + 1), self.max_height / (n + 1)))
    cell = math.max(cell, 10)
    self.cell  = cell
    self.clue_w = cell
    self.w     = cell * (n + 1)
    self.h     = cell * (n + 1)
    self.dimen = Geom:new{ w = self.w, h = self.h }

    -- Clue digits must fit inside their clue_w x cell band; size against the
    -- widest possible clue (a full row/column of ships = n).
    local fit = math.floor(cell * 0.6)
    local fs  = bsearchFont("cfont", 7, math.max(7, cell), fit, fit, string.rep("8", #tostring(n)))
    self.num_face = Font:getFace("cfont", fs)
    self.sym_face = Font:getFace("cfont", bsearchFont("cfont", 6, math.max(6, cell), fit, fit, "8"))

    self.paint_rect = nil

    self.ges_events = {
        CellTap  = { GestureRange:new{ ges = "tap",          range = function() return self.paint_rect end } },
        CellHold = { GestureRange:new{ ges = "hold_release", range = function() return self.paint_rect end } },
    }
end

local function centeredText(bb, text, face, cx, cy, color)
    local m = RenderText:sizeUtf8Text(0, math.huge, face, text, true, false)
    local tx = cx - math.floor(m.x / 2)
    local ty = cy + math.floor((m.y_top - m.y_bottom) / 2)
    RenderText:renderUtf8Text(bb, tx, ty, face, text, true, false, color or Blitbuffer.COLOR_BLACK)
end

-- Layout: row clues in a clue_w band on the left, column clues in a clue_w
-- band below the grid, so the whole thing fits in (n+1) x (n+1) cells.
function BattleshipBoardWidget:_cellOrigin(r, c)
    local x = self.paint_rect.x + self.clue_w + (c - 1) * self.cell
    local y = self.paint_rect.y + (r - 1) * self.cell
    return x, y
end

function BattleshipBoardWidget:_hitTest(gx, gy)
    if not self.paint_rect then return nil end
    local lx = gx - self.paint_rect.x - self.clue_w
    local ly = gy - self.paint_rect.y
    if lx < 0 or ly < 0 then return nil end
    local c = math.floor(lx / self.cell) + 1
    local r = math.floor(ly / self.cell) + 1
    local n = self.board.n
    if r >= 1 and r <= n and c >= 1 and c <= n then return r, c end
    return nil
end

function BattleshipBoardWidget:onCellTap(_, ges)
    local r, c = self:_hitTest(ges.pos.x, ges.pos.y)
    if r and self.cellTapCallback then self.cellTapCallback(r, c) end
    return true
end

function BattleshipBoardWidget:onCellHold(_, ges)
    local r, c = self:_hitTest(ges.pos.x, ges.pos.y)
    if r and self.cellHoldCallback then self.cellHoldCallback(r, c) end
    return true
end

function BattleshipBoardWidget:refresh()
    UIManager:setDirty(self, function()
        return "ui", self.paint_rect or self.dimen
    end)
end

function BattleshipBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local board = self.board
    local n     = board.n
    local cell  = self.cell
    local cw    = self.clue_w
    local thin  = 1

    bb:paintRect(x, y, self.w, self.h, C_BG)

    for r = 1, n do
        for c = 1, n do
            local cx, cy = self:_cellOrigin(r, c)
            local mark  = board.marks[r][c]
            local given = board.given[r][c]
            local wrong = board.wrong_cells and board.wrong_cells[r][c]

            local bg
            if given then
                bg = board.solution[r][c] and C_GIVEN or C_WATER
            elseif wrong then
                bg = C_WRONG
            elseif mark == BattleshipBoard.MARK_SHIP  then bg = C_SHIP
            elseif mark == BattleshipBoard.MARK_WATER then bg = C_WATER
            else bg = C_UNKNOWN
            end

            local pad = math.max(1, math.floor(cell * 0.05))
            bb:paintRect(cx + pad, cy + pad, cell - 2*pad, cell - 2*pad, bg)

            if mark == BattleshipBoard.MARK_SHIP or (given and board.solution[r][c]) then
                -- Draw a small filled rectangle to indicate ship
                local s = math.max(2, math.floor(cell * 0.4))
                local ox = cx + math.floor((cell - s) / 2)
                local oy = cy + math.floor((cell - s) / 2)
                bb:paintRect(ox, oy, s, s, C_FG)
            elseif mark == BattleshipBoard.MARK_WATER or (given and not board.solution[r][c]) then
                centeredText(bb, "\xC2\xB7", self.sym_face,
                    cx + math.floor(cell / 2), cy + math.floor(cell / 2), C_FG)
            end
        end
    end

    -- Grid lines
    local gx = x + cw
    local gy = y
    local gw = cell * n
    local gh = cell * n
    for i = 0, n do
        drawLine(bb, gx + i*cell, gy,       thin, gh, C_GRID)
        drawLine(bb, gx,           gy + i*cell, gw, thin, C_GRID)
    end
    local bw = math.max(2, thin)
    drawLine(bb, gx,          gy,          gw, bw, C_FG)
    drawLine(bb, gx,          gy + gh - bw, gw, bw, C_FG)
    drawLine(bb, gx,          gy,          bw, gh, C_FG)
    drawLine(bb, gx + gw - bw, gy,         bw, gh, C_FG)

    -- Row clues
    for r = 1, n do
        local cy = y + (r-1)*cell + math.floor(cell / 2)
        local cx = x + math.floor(cw / 2)
        centeredText(bb, tostring(board.row_clues[r] or 0), self.num_face, cx, cy, C_FG)
    end

    -- Col clues
    for c = 1, n do
        local cx = x + cw + (c-1)*cell + math.floor(cell / 2)
        local cy = y + gh + math.floor(cw / 2)
        centeredText(bb, tostring(board.col_clues[c] or 0), self.num_face, cx, cy, C_FG)
    end
end

-- ---------------------------------------------------------------------------
-- FleetWidget: the fleet as ship glyphs, one block per cell. Ships still to
-- find are solid black; finished ones (BattleshipBoard:fleetFound) turn light
-- grey with a line through them. One row when it fits at a readable size,
-- else two (the big ships, then the small ones), e.g. the landscape panel.
-- ---------------------------------------------------------------------------

local Screen = require("device").screen

local FleetWidget = InputContainer:extend{
    board     = nil,
    max_width = 0,
}

-- Ship lengths in drawing order, one entry per ship: 4 3 3 2 2 2 1 1 1 1.
local function fleetShips()
    local ships = {}
    for _, spec in ipairs(BattleshipBoard.FLEET) do
        for _ = 1, spec[2] do ships[#ships + 1] = spec[1] end
    end
    return ships
end

-- Width of a row of ships with block size u (blocks touch, 1px seam drawn
-- inside; one block of space between ships).
local function rowWidth(row, u)
    local w = 0
    for i, len in ipairs(row) do
        w = w + len * u
        if i > 1 then w = w + u end
    end
    return w
end

function FleetWidget:init()
    local ships = fleetShips()
    local max_u = Screen:scaleBySize(14)
    local min_u = Screen:scaleBySize(11)
    local u = math.min(max_u, math.floor(self.max_width / rowWidth(ships, 1)))
    if u >= min_u then
        self.rows = { ships }
    else
        -- Big ships (4, 3) on the first row, the small ones below.
        local top, bottom = {}, {}
        for _, len in ipairs(ships) do
            if len >= 3 then top[#top + 1] = len else bottom[#bottom + 1] = len end
        end
        self.rows = { top, bottom }
        local widest = math.max(rowWidth(top, 1), rowWidth(bottom, 1))
        u = math.min(max_u, math.floor(self.max_width / widest))
    end
    self.u = math.max(4, u)
    self.row_gap = math.floor(self.u * 0.6)
    local w = 0
    for _, row in ipairs(self.rows) do w = math.max(w, rowWidth(row, self.u)) end
    self.w = w
    self.h = #self.rows * self.u + (#self.rows - 1) * self.row_gap
    self.dimen = Geom:new{ w = self.w, h = self.h }
end

function FleetWidget:getSize()
    return Geom:new{ w = self.w, h = self.h }
end

function FleetWidget:refresh()
    UIManager:setDirty(self, function()
        return "ui", self.paint_rect or self.dimen
    end)
end

function FleetWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local u = self.u
    -- Finished ships of each length, greyed from the right of each group.
    local found = self.board:fleetFound()
    local remaining = {}
    for _, spec in ipairs(BattleshipBoard.FLEET) do
        remaining[spec[1]] = spec[2] - math.min(spec[2], found[spec[1]] or 0)
    end
    bb:paintRect(x, y, self.w, self.h, C_BG)
    local seen = {}
    for ri, row in ipairs(self.rows) do
        local rx = x + math.floor((self.w - rowWidth(row, u)) / 2)
        local ry = y + (ri - 1) * (u + self.row_gap)
        for _, len in ipairs(row) do
            seen[len] = (seen[len] or 0) + 1
            local done = seen[len] > remaining[len]
            local sw = len * u
            if done then
                bb:paintRect(rx, ry, sw, u, Blitbuffer.COLOR_GRAY_D)
                bb:paintBorder(rx, ry, sw, u, 1, Blitbuffer.COLOR_GRAY_9)
                for k = 1, len - 1 do
                    drawLine(bb, rx + k * u, ry, 1, u, Blitbuffer.COLOR_GRAY_9)
                end
                drawLine(bb, rx, ry + math.floor(u / 2), sw, math.max(1, math.floor(u / 8)), C_FG)
            else
                bb:paintRect(rx, ry, sw, u, C_FG)
                -- Seams between the blocks, so lengths can be counted.
                for k = 1, len - 1 do
                    drawLine(bb, rx + k * u, ry + 2, 1, u - 4, C_BG)
                end
            end
            rx = rx + sw + u
        end
    end
end

BattleshipBoardWidget.FleetWidget = FleetWidget

return BattleshipBoardWidget
