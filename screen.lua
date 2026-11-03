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
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local Widget          = require("ui/widget/widget")
local _               = require("i18n")
local T               = require("ffi/util").template

local MenuHelper  = require("menu_helper")
local Party       = require("party")
local ScreenBase  = require("screen_base")

local CalcBoard = lrequire("board")
local Match     = lrequire("match")

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
-- TimerBox — the countdown text, remembering where it was painted so a tick
-- refreshes only its own rectangle.
-- ---------------------------------------------------------------------------

local TimerBox = Widget:extend{ text_widget = nil }

function TimerBox:getSize()
    return self.text_widget:getSize()
end

function TimerBox:setText(text)
    self.text_widget:setText(text)
end

function TimerBox:paintTo(bb, x, y)
    local sz = self.text_widget:getSize()
    self.dimen = Geom:new{ x = x, y = y, w = sz.w, h = sz.h }
    self.text_widget:paintTo(bb, x, y)
end

function TimerBox:free()
    self.text_widget:free()
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

local PARTY_RULES_EN = [[
Mental Math · multiplayer — Rules

A buzzer game for 2 to 8 players around one reader laid in the middle of the table. Nobody touches the answers: the reader shows the calculation, players shout.

SETUP
In the menu: Players and Player names, Difficulty (the kind of calculations), Questions (10, 15, 20 or 30 per match) and Time limit (none, or 5 to 20 s per question).

HOW A QUESTION GOES
A calculation is shown very big. The first player to shout the right answer wins it — a wrong shout doesn't stop the others. Whoever is closest to the reader taps Answer to show the result (with a time limit it is shown when the time runs out). The reader then asks who found it: tap the name of the player who was first and right, or Nobody. The next calculation comes up at once.

SCORING
One point for the player who was first and right; nothing for anyone else, no penalty for a wrong shout. The status line shows the question number and the scores.

END OF THE MATCH
After the last question the player with the most points wins; equal totals are a tie. New game starts a new match.
]]

local PARTY_RULES_FR = [[
Calcul Mental · à plusieurs — Règles

Un jeu de rapidité pour 2 à 8 joueurs autour d'une liseuse posée au milieu de la table. Personne ne touche les réponses : la liseuse affiche le calcul, les joueurs crient.

PRÉPARATION
Dans le menu : Joueurs et Noms des joueurs, Difficulté (le type de calculs), Questions (10, 15, 20 ou 30 par partie) et Temps limite (aucun, ou de 5 à 20 s par question).

DÉROULEMENT D'UNE QUESTION
Un calcul s'affiche en très grand. Le premier qui crie la bonne réponse la remporte — une mauvaise réponse n'arrête pas les autres. Le joueur le plus proche de la liseuse touche Réponse pour afficher le résultat (avec un temps limite, il s'affiche à la fin du temps). La liseuse demande ensuite qui a trouvé : touchez le nom du joueur qui a répondu juste le premier, ou Personne. Le calcul suivant s'affiche aussitôt.

POINTS
Un point pour le joueur qui a répondu juste le premier ; rien pour les autres, pas de pénalité pour une mauvaise réponse. La ligne d'état montre le numéro de la question et les scores.

FIN DE PARTIE
Après la dernière question, le joueur qui a le plus de points gagne ; à total égal, c'est une égalité. Nouvelle partie lance une nouvelle partie.
]]

local MODE_RULES = {
    solo  = { GAME_RULES_EN, GAME_RULES_FR },
    party = { PARTY_RULES_EN, PARTY_RULES_FR },
}

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

    self.party = self.plugin.launch_mode == "party"
    if self.party then self:_initParty() end

    ScreenBase.init(self)  -- calls buildLayout()
    if self.party then
        self:_resumeParty()
    else
        self:_nextQuestion()
    end
end

function CalcScreen:serializeState()
    return self.board:serialize()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function CalcScreen:buildLayout()
    if self.party then return self:_buildPartyLayout() end
    local is_landscape = self:isLandscape()

    -- Title bar with Options menu
    local title_bar = self:buildTitleBar(_("Mental Math"), function()
        return {
            { text = _("New game"), callback = function() self:onNewSession() end },
            { text = T(_("Difficulty: %1"), self:_getDiffButtonText()),
              callback = function() self:openDifficultyMenu() end },
            self:_modeMenuItem(),
            self:makeModeRulesButtonConfig(MODE_RULES),
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
    if not msg and self.party and self.match then
        ScreenBase.updateStatus(self, self:joinStatus(
            T(_("Question %1/%2"), Match.current(self.match), self.match.questions),
            Party.statusText(self.match.scores)))
        return
    end
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
            if self.party then
                self.qboard.difficulty = id
                self:_newMatch()
                return
            end
            local btn = self.action_buttons and self.action_buttons:getButtonById("diff_btn")
            if btn then btn:setText(self:_getDiffButtonText(), btn.width) end
            self:onNewSession()
        end,
        parent = self,
    }
end

-- ---------------------------------------------------------------------------
-- Mode (solo / multiplayer)
-- ---------------------------------------------------------------------------

function CalcScreen:_modeMenuItem()
    return {
        text = T(_("Mode: %1"), self.party and _("Multiplayer") or _("Solo")),
        callback = function()
            MenuHelper.openPickerMenu{
                title      = _("Mode"),
                items      = { { id = "solo", text = _("Solo") },
                               { id = "party", text = _("Multiplayer") } },
                current_id = self.party and "party" or "solo",
                parent     = self,
                on_select  = function(mode) self:setMode(mode) end,
            }
        end,
    }
end

-- Switches mode and starts a new game in it.
function CalcScreen:setMode(mode)
    self:_stopCountdown()
    if self.party then self:_saveParty() end
    self.plugin.launch_mode = mode
    self.party = mode == "party"
    if self.party then
        self.qboard = CalcBoard:new{ difficulty = self.plugin:getSetting("difficulty", "easy") }
        self:_newMatch()
    else
        self.match = nil
        self:buildLayout()
        self:_nextQuestion()
    end
end

-- ---------------------------------------------------------------------------
-- Multiplayer ("buzzer"): one big calculation, players shout, the device
-- reveals and records who was first. The solo board (self.board) and its
-- saved stats are left alone; questions come from self.qboard and the match
-- is saved under its own key.
-- ---------------------------------------------------------------------------

function CalcScreen:_partyQuestions()
    return tonumber(self.plugin:getSetting("party_questions", Match.DEFAULT_QUESTIONS))
        or Match.DEFAULT_QUESTIONS
end

function CalcScreen:_partyTime()
    return tonumber(self.plugin:getSetting("party_time", Match.DEFAULT_TIME)) or Match.DEFAULT_TIME
end

-- Before the first layout: restore the saved match, or set up a new one.
function CalcScreen:_initParty()
    self.qboard = CalcBoard:new{ difficulty = self.plugin:getSetting("difficulty", "easy") }
    self.time_remaining = 0
    local saved = self.plugin:loadState("party_state")
    self.match = saved and Match.restore(saved.match)
    if self.match then
        self.time_remaining = tonumber(saved.time_remaining) or 0
    else
        local names = Party.loadPlayers(self.plugin, Party.loadCount(self.plugin))
        self.match = Match.new(names, self:_partyQuestions())
    end
end

-- After the first layout: pick up where the restored match was.
function CalcScreen:_resumeParty()
    local m = self.match
    if m.phase == "done" and not m.finished then
        self:_nextPartyQuestion()
    elseif m.phase == "asking" then
        local limit = self:_partyTime()
        if limit > 0 then self:_startCountdown(self.time_remaining > 0 and self.time_remaining or limit) end
    end
end

function CalcScreen:_newMatch()
    self:_stopCountdown()
    local names = Party.loadPlayers(self.plugin, Party.loadCount(self.plugin))
    self.match = Match.new(names, self:_partyQuestions())
    self:_nextPartyQuestion()
end

function CalcScreen:onNewGame()
    if self.party then self:_newMatch() else self:onNewSession() end
end

function CalcScreen:_nextPartyQuestion()
    self:_stopCountdown()
    math.randomseed(os.time() + Match.current(self.match))
    self.qboard:generate()
    Match.ask(self.match, self.qboard.question, self.qboard.answer)
    local limit = self:_partyTime()
    if limit > 0 then self:_startCountdown(limit) end
    self:_saveParty()
    self:_refreshParty()
end

function CalcScreen:onRevealAnswer()
    self:_stopCountdown()
    if not Match.reveal(self.match) then return end
    self:_saveParty()
    self:_refreshParty()
    self:askWhoFound()
end

function CalcScreen:askWhoFound()
    if self.match.phase ~= "revealed" then return end
    -- The dialog sits over the board, so it repeats the answer in its title.
    Party.askWhoFound(self.match.scores.names, {
        title   = Match.answerText(self.match.question, self.match.answer)
            .. "\n" .. _("Who found it?"),
        on_pick = function(i) self:onFound(i) end,
    })
end

-- i: the player who was first and right, nil for nobody.
function CalcScreen:onFound(i)
    local m = self.match
    if not Match.give(m, i) then return end
    if m.finished then
        self:_saveParty()
        self:_refreshParty()
        Party.showScoreboard(m.scores, { final = true })
    else
        self:_nextPartyQuestion()
    end
end

function CalcScreen:isRoundOver()
    return self.party and self.match ~= nil and self.match.finished
end

function CalcScreen:_saveParty()
    if not self.match then return end
    self.plugin:saveState({
        match = Match.serialize(self.match),
        time_remaining = self.time_remaining,
    }, "party_state")
end

function CalcScreen:closeScreen()
    self:_stopCountdown()
    if self.party then self:_saveParty() end
    ScreenBase.closeScreen(self)
end

function CalcScreen:_refreshParty()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- Countdown (optional per-question time limit) ------------------------------

function CalcScreen:_startCountdown(duration)
    self.time_remaining = duration
    self._tick_gen = (self._tick_gen or 0) + 1
    local gen = self._tick_gen
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

function CalcScreen:_stopCountdown()
    self._tick_gen = (self._tick_gen or 0) + 1
end

function CalcScreen:_onTick(gen)
    if gen ~= self._tick_gen then return end
    self.time_remaining = math.max(0, self.time_remaining - 1)
    if self.timer_widget then
        self.timer_widget:setText(self:_timerText())
        local box = self.timer_widget.dimen
        UIManager:setDirty(self, function() return "fast", box or self.dimen end)
    end
    if self.time_remaining <= 0 then
        self:onRevealAnswer()
    else
        UIManager:scheduleIn(1, function() self:_onTick(gen) end)
    end
end

function CalcScreen:_timerText()
    return string.format("%d:%02d", math.floor(self.time_remaining / 60), self.time_remaining % 60)
end

-- Menu ----------------------------------------------------------------------

local function pickNumber(screen, title, values, current, fmt, on_pick)
    local items = {}
    for _i, v in ipairs(values) do items[#items + 1] = { id = v, text = fmt(v) } end
    MenuHelper.openPickerMenu{
        title = title, items = items, current_id = current,
        parent = screen, on_select = on_pick,
    }
end

local function limitText(v)
    return v > 0 and T(_("%1 s"), v) or _("None")
end

function CalcScreen:_partyMenu()
    return {
        { text = _("New game"), callback = function() self:_newMatch() end },
        { text = T(_("Players: %1"), #self.match.scores.names), callback = function()
            Party.pickCount(self.plugin, function() self:_newMatch() end, self)
        end },
        { text = _("Player names"), callback = function()
            Party.editPlayers(self.plugin, self.match.scores.names, function()
                self:_saveParty()
                self:_refreshParty()
            end, self)
        end },
        { text = T(_("Difficulty: %1"), self:_getDiffButtonText()),
          callback = function() self:openDifficultyMenu() end },
        { text = T(_("Questions: %1"), self.match.questions), callback = function()
            pickNumber(self, _("Questions"), Match.QUESTION_CHOICES, self.match.questions, tostring,
                function(n)
                    self.plugin:saveSetting("party_questions", n)
                    self:_newMatch()
                end)
        end },
        { text = T(_("Time limit: %1"), limitText(self:_partyTime())), callback = function()
            pickNumber(self, _("Time limit"), Match.TIME_CHOICES, self:_partyTime(), limitText,
                function(n) self.plugin:saveSetting("party_time", n) end)
        end },
        self:_modeMenuItem(),
        self:makeModeRulesButtonConfig(MODE_RULES),
    }
end

-- Layout --------------------------------------------------------------------

function CalcScreen:_partyButtons()
    local m = self.match
    if m.phase == "asking" then
        return { { text = _("Answer"), callback = function() self:onRevealAnswer() end } }
    elseif m.phase == "revealed" then
        return { { text = _("Who found it?"), callback = function() self:askWhoFound() end } }
    end
    -- "done" and not finished only lasts until the next question is up.
    return { { text = _("Next question"), callback = function() self:_nextPartyQuestion() end } }
end

function CalcScreen:_buildPartyLayout()
    local is_landscape = self:isLandscape()
    local m = self.match
    local title_bar = self:buildTitleBar(_("Mental Math"), function()
        return self:_partyMenu()
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar(self:_partyButtons()),
    }

    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    local vs = Size.span.vertical_large
    local board = VerticalGroup:new{ align = "center" }
    self.timer_widget = nil
    if m.finished then
        local leaders = Party.leaders(m.scores)
        local head = #leaders == 1 and T(_("%1 wins!"), m.scores.names[leaders[1]])
            or _("It's a tie!")
        local q_h = math.floor(budget_h * 0.25)
        self.question_widget = QuestionWidget:new{ text = head, width = budget_w, height = q_h }
        board[1] = self.question_widget
        board[2] = VerticalSpan:new{ width = vs }
        board[3] = TextBoxWidget:new{
            text = table.concat(Party.scoreLines(m.scores), "\n"),
            face = Font:getFace("infofont", math.max(14, math.floor(math.min(budget_w / 14,
                budget_h / 12) / DPI_SCALE))),
            width = budget_w, alignment = "center",
            height = math.max(1, budget_h - q_h - vs), height_adjust = true,
            height_overflow_show_ellipsis = true,
        }
    else
        local used = 0
        if m.phase == "asking" and self:_partyTime() > 0 then
            self.timer_widget = TimerBox:new{ text_widget = TextWidget:new{
                text = self:_timerText(),
                face = Font:getFace("cfont", math.max(12, math.floor(
                    math.min(budget_w, budget_h) * 0.14 / (DeviceScreen:scaleBySize(1000) / 1000)))),
                max_width = budget_w,
            } }
            board[#board + 1] = self.timer_widget
            board[#board + 1] = VerticalSpan:new{ width = vs }
            used = self.timer_widget:getSize().h + vs
        end
        local text = m.phase == "asking" and m.question
            or Match.answerText(m.question, m.answer)
        self.question_widget = QuestionWidget:new{
            text = text or "", width = budget_w,
            height = math.max(40, math.min(budget_h - used, math.floor(budget_w * 0.6))),
        }
        board[#board + 1] = self.question_widget
    end

    if is_landscape then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            board,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, board,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

return CalcScreen
