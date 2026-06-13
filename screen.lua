-- ---------------------------------------------------------------------------
-- CalcScreen — quiz screen for Calcul Mental (mental arithmetic)
--
-- Presents an arithmetic question and four multiple-choice answer buttons.
-- ---------------------------------------------------------------------------

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer      = require("ffi/blitbuffer")
local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local RenderText      = require("ui/rendertext")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")

local MenuHelper  = require("menu_helper")
local ScreenBase  = require("screen_base")

local CalcBoard = lrequire("board")

local DeviceScreen = Device.screen

-- ---------------------------------------------------------------------------
-- QuestionWidget — draws the arithmetic question in large text
-- ---------------------------------------------------------------------------

local QuestionWidget = InputContainer:extend{
    text      = "",
    font_size = 32,
    width     = 200,
    height    = 80,
}

function QuestionWidget:init()
    self.face  = Font:getFace("cfont", self.font_size)
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function QuestionWidget:setText(text)
    self.text = text
    UIManager:setDirty(self, function()
        return "ui", Geom:new{ x = self.dimen.x or 0, y = self.dimen.y or 0,
                               w = self.width,         h = self.height }
    end)
end

function QuestionWidget:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)

    local face = self.face
    local text = self.text
    local m    = RenderText:sizeUtf8Text(0, self.width, face, text, true, false)
    local fh   = m.y_bottom - m.y_top
    local tx   = x + math.floor((self.width  - m.x) / 2)
    local ty   = y + math.floor((self.height - fh)  / 2) + math.abs(m.y_top)
    RenderText:renderUtf8Text(bb, tx, ty, face, text, true, false, Blitbuffer.COLOR_BLACK)
end

-- ---------------------------------------------------------------------------
-- CalcScreen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
Mental Arithmetic — Rules

Solve arithmetic exercises as quickly and accurately as possible.

Each exercise shows an equation with a missing value or operator. Select the correct answer from the choices shown, or type it using the keyboard.

Operations include:
• Addition (+)
• Subtraction (−)
• Multiplication (×)
• Division (÷)

Score points for speed and accuracy. Difficulty increases as you progress.
]])

local GAME_RULES_FR = [[
Calcul Mental — Règles

Résolvez des exercices d'arithmétique aussi vite et précisément que possible.

Un calcul est affiché avec une valeur manquante. Appuyez sur la bonne réponse parmi les choix proposés, ou saisissez-la au clavier.

Les opérations comprennent :
• Addition (+)
• Soustraction (−)
• Multiplication (×)
• Division (÷)

Marquez des points pour la rapidité et la précision. La difficulté augmente avec vos progrès.
]]

local CalcScreen = ScreenBase:extend{}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function CalcScreen:init()
    local state = self.plugin:loadState()
    local diff  = self.plugin:getSetting("difficulty", "easy")

    self.board = CalcBoard:new{ difficulty = diff }
    self.board:load(state)

    -- Pending: a brief lock after answering to show feedback
    self._locked = false

    ScreenBase.init(self)  -- calls buildLayout()
    self:_nextQuestion()
end

function CalcScreen:serializeState()
    return self.board:serialize()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function CalcScreen:buildLayout()
    local sw = DeviceScreen:getWidth()
    local is_landscape = self:isLandscape()

    local panel_w = is_landscape
        and math.floor(sw * 0.55)
        or  math.floor(sw * 0.92)

    -- Question display area
    local q_font_size = math.max(20, math.floor(panel_w * 0.09))
    local q_height    = math.ceil(q_font_size * 2.2)
    self.question_widget = QuestionWidget:new{
        text      = "",
        font_size = q_font_size,
        width     = panel_w,
        height    = q_height,
    }

    -- Action buttons: New | Difficulty | Close
    local action_buttons = ButtonTable:new{
        width                 = panel_w,
        shrink_unneeded_width = true,
        buttons = {{
            { text = _("Nouveau"),
              callback = function() self:onNewSession() end },
            { text = self:_getDiffButtonText(),
              callback = function() self:openDifficultyMenu() end,
              id = "diff_btn" },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
            self:makeCloseButtonConfig(),
        }},
    }
    self.action_buttons = action_buttons

    -- Answer buttons (2 × 2 grid, rebuilt each question)
    self.answer_table = self:_buildAnswerTable(panel_w)

    local q_frame = FrameContainer:new{
        padding    = Size.padding.large,
        background = Blitbuffer.COLOR_WHITE,
        self.question_widget,
    }

    local center_panel = VerticalGroup:new{
        align = "center",
        action_buttons,
        VerticalSpan:new{ width = Size.span.vertical_large },
        q_frame,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self.answer_table,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self.status_text,
    }

    if is_landscape then
        self.layout = HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            center_panel,
        }
    else
        self.layout = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            center_panel,
            VerticalSpan:new{ width = Size.span.vertical_large },
        }
    end

    self[1] = self.layout
    self:updateStatus()
end

-- Build 2×2 ButtonTable for the 4 answer choices
function CalcScreen:_buildAnswerTable(width)
    local opts = self.board.options or { 0, 1, 2, 3 }
    local function makeCallback(val)
        return function() self:onAnswer(val) end
    end
    return ButtonTable:new{
        width                 = width,
        shrink_unneeded_width = true,
        buttons = {
            {
                { text = tostring(opts[1] or "?"), callback = makeCallback(opts[1]) },
                { text = tostring(opts[2] or "?"), callback = makeCallback(opts[2]) },
            },
            {
                { text = tostring(opts[3] or "?"), callback = makeCallback(opts[3]) },
                { text = tostring(opts[4] or "?"), callback = makeCallback(opts[4]) },
            },
        },
    }
end

-- ---------------------------------------------------------------------------
-- Question flow
-- ---------------------------------------------------------------------------

function CalcScreen:_nextQuestion()
    math.randomseed(os.time() + self.board.total)
    self.board:generate()
    self._locked = false
    if self.question_widget then
        self.question_widget:setText(self.board.question or "")
    end
    -- Rebuild answer buttons with new options
    self:_refreshAnswerTable()
    self:updateStatus()
end

function CalcScreen:_refreshAnswerTable()
    if not self.answer_table then return end

    local sw        = DeviceScreen:getWidth()
    local is_land   = self:isLandscape()
    local panel_w   = is_land and math.floor(sw * 0.55) or math.floor(sw * 0.92)
    local new_table = self:_buildAnswerTable(panel_w)

    -- Replace answer_table in the VerticalGroup (it is always at index 4 in center_panel)
    -- Easier: rebuild the full layout
    self:buildLayout()
    if self.question_widget then
        self.question_widget:setText(self.board.question or "")
    end
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- ---------------------------------------------------------------------------
-- Answer handler
-- ---------------------------------------------------------------------------

function CalcScreen:onAnswer(choice)
    if self._locked then return end
    if self.board.status ~= "playing" then return end

    self._locked = true
    local ok     = self.board:checkAnswer(choice)
    self.plugin:saveState(self:serializeState())
    self:updateStatus()

    local delay = ok and 0.4 or 0.8
    UIManager:scheduleIn(delay, function()
        self:_nextQuestion()
    end)
end

-- ---------------------------------------------------------------------------
-- New session (reset score)
-- ---------------------------------------------------------------------------

function CalcScreen:onNewSession()
    self.board:resetStats()
    self.plugin:saveState(self:serializeState())
    self:_nextQuestion()
end

-- ---------------------------------------------------------------------------
-- Status bar
-- ---------------------------------------------------------------------------

function CalcScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    else
        local board  = self.board
        local total  = board.total
        local corr   = board.correct
        local streak = board.streak
        local last   = board.last_ok
        local pct    = (total > 0) and math.floor(corr * 100 / total) or 0

        local feedback = ""
        if last == true then
            feedback = "  \xe2\x9c\x93"  -- UTF-8 checkmark ✓
        elseif last == false then
            feedback = "  \xe2\x9c\x97"  -- UTF-8 cross ✗
        end

        if total == 0 then
            status = _("Choisissez une réponse !")
        else
            if streak >= 3 then
                status = string.format(_("%d/%d (%d%%)  Série: %d%s"),
                    corr, total, pct, streak, feedback)
            else
                status = string.format(_("%d/%d (%d%%)%s"), corr, total, pct, feedback)
            end
        end
    end
    ScreenBase.updateStatus(self, status)
end

-- ---------------------------------------------------------------------------
-- Difficulty menu
-- ---------------------------------------------------------------------------

function CalcScreen:_getDiffButtonText()
    local diff   = self.plugin:getSetting("difficulty", "easy")
    return MenuHelper.DIFFICULTY_LABELS[diff] or diff
end

function CalcScreen:openDifficultyMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "easy"),
        on_select = function(id)
            self.plugin:saveSetting("difficulty", id)
            self.board.difficulty = id
            local btn = self.action_buttons and self.action_buttons:getButtonById("diff_btn")
            if btn then btn:setText(self:_getDiffButtonText(), btn.width) end
            self:onNewSession()
        end,
        parent = self,
    }
end

return CalcScreen
