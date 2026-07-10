local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
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

local DeviceScreen = Device.screen

-- ---------------------------------------------------------------------------
-- BattleshipScreen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
Battleship (Bimaru) — Rules

Find the hidden fleet in the grid using the row and column clues.

The fleet consists of ships of various lengths (carrier, battleship, destroyer, submarine, etc.).
Row and column clues show the total number of ship segments in each line.
Ships are placed horizontally or vertically and cannot touch each other, even diagonally.

Tap a cell to toggle it between water and ship. Long-press to mark it as definite water.
]])

local GAME_RULES_FR = [[
Bataille Navale (Bimaru) — Règles

Trouvez la flotte cachée dans la grille à l'aide des indices de lignes et de colonnes.

La flotte comprend des navires de différentes longueurs.
Les indices de lignes et de colonnes indiquent le nombre total de segments de navires dans chaque ligne.
Les navires sont placés horizontalement ou verticalement et ne peuvent pas se toucher, même en diagonale.

Appuyez sur une case pour la basculer entre eau et navire. Appui long pour marquer une case comme eau certaine.
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

function BattleshipScreen:serializeState()
    return self.board:serialize()
end

function BattleshipScreen:buildLayout()
    local sw           = DeviceScreen:getWidth()
    local sh = DeviceScreen:getHeight()
    local is_landscape = self:isLandscape()

    local btn_width = is_landscape
        and math.max(math.floor(sw * 0.35), 100)
        or  math.floor(sw * 0.9)

    local top_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = btn_width,
        buttons = {{
            { text = _("New"),  callback = function() self:onNewGame() end },
            { id = "size_btn",  text = self:_sizeLabel(),
              callback = function() self:openSizeMenu() end },
            { id = "diff_btn",  text = self:_diffLabel(),
              callback = function() self:openDiffMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
            self:makeCloseButtonConfig(),
        }},
    }
    self.size_btn = top_buttons:getButtonById("size_btn")
    self.diff_btn = top_buttons:getButtonById("diff_btn")

    local margin      = Size.margin.default
    local padding     = Size.padding.large
    local frame_extra = (padding + margin) * 2
    local board_max
    if is_landscape then
        board_max = math.min(sw - math.floor(sw * 0.4) - frame_extra, sh - frame_extra)
    else
        board_max = math.min(sw - frame_extra, sh - 160 - frame_extra)
    end
    board_max = math.max(board_max, 80)

    self.board_widget = BattleshipBoardWidget:new{
        board      = self.board,
        max_width  = board_max,
        max_height = board_max,
        cellTapCallback  = function(r, c) self:onCellTap(r, c) end,
        cellHoldCallback = function(r, c) self:onCellHold(r, c) end,
    }

    local board_frame = FrameContainer:new{
        padding = padding,
        margin  = margin,
        self.board_widget,
    }

    local bottom_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = btn_width,
        buttons = {{
            { text = _("Undo"),   callback = function() self:onUndo() end },
            { text = _("Check"),  callback = function() self:onCheck() end },
            { text = _("Reveal"), callback = function() self:onReveal() end },
        }},
    }

    if is_landscape then
        local panel = VerticalGroup:new{
            align = "center",
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            bottom_buttons,
        }
        self.layout = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            panel,
        }
    else
        local content = VerticalGroup:new{
            align = "center",
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
        }
        self:buildPortraitLayout(top_buttons, content, bottom_buttons)
    end
    self[1] = self.layout
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
        title      = _("Grid size"),
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
        status = T(_("Ships: %1/%2  Tap=cycle  Hold=water"), ships, total_ship_cells)
    end
    ScreenBase.updateStatus(self, status)
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
