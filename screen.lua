local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase            = require("screen_base")
local MenuHelper            = require("menu_helper")
local BattleshipBoard       = lrequire("board")
local BattleshipBoardWidget = lrequire("board_widget")

-- ---------------------------------------------------------------------------
-- BattleshipScreen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
Battleship (Bimaru) — Rules

Find the hidden fleet in the grid using the row and column clues.

The fleet consists of ships of various lengths (carrier, battleship, destroyer, submarine, etc.).
Row and column clues show the total number of ship segments in each line.
Ships are placed horizontally or vertically and cannot touch each other, even diagonally.

Tap a cell to cycle it: ship, then water, then empty again. Long-press a cell to mark it as water directly.
]])

local GAME_RULES_FR = [[
Bataille Navale (Bimaru) — Règles

Trouvez la flotte cachée dans la grille à l'aide des indices de lignes et de colonnes.

La flotte comprend des navires de différentes longueurs.
Les indices de lignes et de colonnes indiquent le nombre total de segments de navires dans chaque ligne.
Les navires sont placés horizontalement ou verticalement et ne peuvent pas se toucher, même en diagonale.

Appuyez sur une case pour la faire passer de navire à eau, puis de nouveau à vide. Appui long pour marquer directement une case comme eau.
]]

local BattleshipScreen = ScreenBase:extend{}

function BattleshipScreen:init()
    local state = self.plugin:loadState()
    local n     = self.plugin:getSetting("grid_n",     BattleshipBoard.DEFAULT_N)
    local diff  = self.plugin:getSetting("difficulty", "medium")
    self.board  = BattleshipBoard:new{ n = n, difficulty = diff }
    if not self.board:load(state) then
        -- fresh puzzle
    end
    ScreenBase.init(self)
end

-- Solved, or the solution revealed (reveal sets won too, and is one-way).
function BattleshipScreen:isRoundOver()
    return self.board.won
end

function BattleshipScreen:serializeState()
    return self.board:serialize()
end

function BattleshipScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Battleship Puzzle"), function()
        return {
            { text = _("New game"),     callback = function() self:onNewGame() end },
            { text = T(_("Size: %1"), self:_sizeLabel()),       callback = function() self:openSizeMenu() end },
            { text = T(_("Difficulty: %1"), self:_diffLabel()), callback = function() self:openDiffMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    local controls_w = self:getControlsWidth()
    self.status_text:setMaxWidth(controls_w)
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar({
            { text = _("Undo"),   callback = function() self:onUndo() end },
            { text = _("Check"),  callback = function() self:onCheck() end },
            { text = _("Hint"),   callback = function() self:onHint() end },
            { text = _("Reveal"), callback = function() self:onReveal() end },
        }),
    }

    local padding     = Size.padding.large
    local frame_extra = 2 * (padding + Size.border.window)
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = BattleshipBoardWidget:new{
        board      = self.board,
        max_width  = budget_w - frame_extra,
        max_height = budget_h - frame_extra,
        cellTapCallback  = function(r, c) self:onCellTap(r, c) end,
        cellHoldCallback = function(r, c) self:onCellHold(r, c) end,
    }

    local board_frame = FrameContainer:new{
        padding = padding,
        margin  = 0,
        self.board_widget,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

function BattleshipScreen:onCellTap(r, c)
    -- Tap: cycle unknown→ship→water
    self.board:cycleCell(r, c)
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

function BattleshipScreen:onCellHold(r, c)
    -- Hold: mark as water
    self.board:setMark(r, c, BattleshipBoard.MARK_WATER)
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

function BattleshipScreen:onUndo()
    self.board:undoMove()
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

function BattleshipScreen:onCheck()
    self.board:check()
    self.board_widget:refresh()
    self:updateStatus()
end

function BattleshipScreen:onReveal()
    self.board:reveal()
    self.board_widget:refresh()
    self:updateStatus(_("Solution revealed."))
    self.plugin:saveState(self.board:serialize())
end

function BattleshipScreen:onNewGame()
    local n    = self.plugin:getSetting("grid_n",     BattleshipBoard.DEFAULT_N)
    local diff = self.plugin:getSetting("difficulty", "medium")
    self.board = BattleshipBoard:new{ n = n, difficulty = diff }
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function BattleshipScreen:openSizeMenu()
    local items = {}
    for _, n in ipairs(BattleshipBoard.SIZES) do
        items[#items + 1] = { id = n, text = string.format("%d\xC3\x97%d", n, n) }
    end
    MenuHelper.openPickerMenu{
        title      = _("Size"),
        items      = items,
        current_id = self.plugin:getSetting("grid_n", BattleshipBoard.DEFAULT_N),
        parent     = self,
        on_select  = function(n)
            self.plugin:saveSetting("grid_n", n)
            if self.size_btn then
                self.size_btn:setText(self:_sizeLabel(), self.size_btn.width)
            end
            self:onNewGame()
        end,
    }
end

function BattleshipScreen:openDiffMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "medium"),
        parent    = self,
        on_select = function(diff)
            self.plugin:saveSetting("difficulty", diff)
            if self.diff_btn then
                self.diff_btn:setText(self:_diffLabel(), self.diff_btn.width)
            end
            self:onNewGame()
        end,
    }
end

function BattleshipScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board.won then
        status = _("Fleet found! Puzzle solved!")
    else
        local ships = 0
        local n = self.board.n
        for r = 1, n do
            for c = 1, n do
                if self.board.marks[r][c] == BattleshipBoard.MARK_SHIP then
                    ships = ships + 1
                end
            end
        end
        local total_ship_cells = 0
        for r = 1, n do total_ship_cells = total_ship_cells + self.board.row_clues[r] end
        status = self:joinStatus(
            T("%1×%1", n),
            self:_diffLabel(),
            T(_("Ships: %1/%2"), ships, total_ship_cells))
    end
    ScreenBase.updateStatus(self, status)
    -- Every mark, undo, hint and reveal ends here.
    self:refreshActionBar()
end

function BattleshipScreen:_sizeLabel()
    local n = self.plugin:getSetting("grid_n", BattleshipBoard.DEFAULT_N)
    return string.format("%d\xC3\x97%d", n, n)
end

function BattleshipScreen:_diffLabel()
    local diff = self.plugin:getSetting("difficulty", "medium")
    local labels = { easy = _("Easy"), medium = _("Medium"), hard = _("Hard") }
    return labels[diff] or diff
end

return BattleshipScreen
