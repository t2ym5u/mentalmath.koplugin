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
local _               = require("i18n")
local T               = require("ffi/util").template

local MenuHelper  = require("menu_helper")
local ScreenBase  = require("screen_base")

local CalcBoard = lrequire("board")

local DeviceScreen = Device.screen

-- ---------------------------------------------------------------------------
-- QuestionWidget — draws the arithmetic question in large text
-- ---------------------------------------------------------------------------

local QuestionWidget = InputContainer:extend{
    text   = "",
    width  = 200,
    height = 80,
}

-- Font:getFace() scales its size by the screen DPI; pixel-derived sizes are
-- divided by this so they come out at the intended pixel size.
local DPI_SCALE = DeviceScreen:scaleBySize(1000) / 1000

function QuestionWidget:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

-- Largest face (up to half the box height) whose ink fits the box. Measured
-- without a width cap: capping at the box width would clip m.x and accept
-- every size, letting a long question run off both sides.
function QuestionWidget:_fitFace(text)
    if self._fit_text == text and self._fit_face then return self._fit_face end
    local max_w = self.width * 0.92
    local max_h = self.height * 0.8
    local size  = math.max(8, math.floor(self.height * 0.5 / DPI_SCALE))
    local face
    while size >= 8 do
        face = Font:getFace("cfont", size)
        local m = RenderText:sizeUtf8Text(0, self.width * 10, face, text, true, false)
        if m.x <= max_w and (m.y_top + m.y_bottom) <= max_h then break end
        size = size - 2
    end
    self._fit_text, self._fit_face = text, face
    return face
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

    local text = self.text
    if text == "" then return end
    local face = self:_fitFace(text)
    local m    = RenderText:sizeUtf8Text(0, self.width * 10, face, text, true, false)
    local tx   = x + math.floor((self.width - m.x) / 2)
    -- Baseline that puts the ink's vertical centre on the box's centre.
    local ty   = y + math.floor(self.height / 2 + (m.y_top - m.y_bottom) / 2)
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
    local is_landscape = self:isLandscape()

    -- Title bar with Options menu
    local title_bar = self:buildTitleBar(_("Mental Math"), function()
        return {
            { text = _("New game"), callback = function() self:onNewSession() end },
            { text = T(_("Difficulty: %1"), self:_getDiffButtonText()),
              callback = function() self:openDifficultyMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    -- Answer pad (rebuilt each question, as the layout is)
    self.status_text:setMaxWidth(self:getControlsWidth())
    self.answer_table = self:_buildAnswerTable()
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self.answer_table,
    }

    -- Question display area: the full budget width, and as tall as a
    -- comfortable reading line allows.
    local frame_pad   = Size.padding.large
    local frame_extra = 2 * (frame_pad + Size.border.window)
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    local q_w = budget_w - frame_extra
    local q_h = math.max(40, math.min(budget_h - frame_extra, math.floor(q_w * 0.4)))
    self.question_widget = QuestionWidget:new{
        text   = self.board.question or "",
        width  = q_w,
        height = q_h,
    }

    local q_frame = FrameContainer:new{
        padding    = frame_pad,
        margin     = 0,
        background = Blitbuffer.COLOR_WHITE,
        self.question_widget,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            q_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, q_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

-- The 4 answer choices as one full-width pad, with numbers big enough to
-- read and hit at a glance.
function CalcScreen:_buildAnswerTable()
    local opts = self.board.options or { 0, 1, 2, 3 }
    local keys = {}
    for i = 1, 4 do
        local v = opts[i]
        keys[i] = {
            text      = tostring(v or "?"),
            font_size = 30,
            font_bold = true,
            height    = DeviceScreen:scaleBySize(80),
            callback  = function() self:onAnswer(v) end,
        }
    end
    return self:buildNumberPad(keys)
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

    -- The answer pad is part of the layout, so rebuilding the layout is the
    -- simplest way to swap it.
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

        local feedback
        if last == true then
            feedback = "\xe2\x9c\x93"  -- UTF-8 checkmark ✓
        elseif last == false then
            feedback = "\xe2\x9c\x97"  -- UTF-8 cross ✗
        end

        if total == 0 then
            status = self:joinStatus(self:_getDiffButtonText(), _("Choose an answer!"))
        else
            status = self:joinStatus(
                self:_getDiffButtonText(),
                T(_("Correct: %1/%2 (%3%)"), corr, total, pct),
                streak >= 3 and T(_("Streak: %1"), streak) or nil,
                feedback)
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
    local items = {}
    for _i, id in ipairs(MenuHelper.DIFFICULTY_ORDER) do
        items[#items + 1] = { id = id, text = MenuHelper.DIFFICULTY_LABELS[id] or id }
    end
    MenuHelper.openPickerMenu{
        title      = _("Difficulty"),
        items      = items,
        current_id = self.plugin:getSetting("difficulty", "easy"),
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
