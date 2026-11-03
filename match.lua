-- ---------------------------------------------------------------------------
-- Match — the multiplayer "buzzer" mode (pure Lua, no UI, tested by busted).
--
-- One calculation at a time is shown very big; players shout the answer.
-- "Answer" reveals it, then whoever was first and right gets the point (or
-- nobody). A match is N questions; the most points wins.
-- ---------------------------------------------------------------------------

local Party = require("party")

local Match = {}

Match.QUESTION_CHOICES = { 10, 15, 20, 30 }
Match.TIME_CHOICES     = { 0, 5, 10, 15, 20 }   -- seconds; 0 = no limit
Match.DEFAULT_QUESTIONS = 10
Match.DEFAULT_TIME      = 0

-- phase: "asking" (question shown) | "revealed" (answer shown, waiting for
-- who found it) | "done" (point given; the match may be finished).
function Match.new(names, questions)
    return {
        scores    = Party.newScores(names),
        questions = questions or Match.DEFAULT_QUESTIONS,
        question  = nil,
        answer    = nil,
        phase     = "done",
        finished  = false,
    }
end

function Match.current(m)
    return m.scores.round
end

-- Puts the next question up; false when the match is over.
function Match.ask(m, question, answer)
    if m.finished or m.scores.round >= m.questions then return false end
    Party.nextRound(m.scores)
    m.question, m.answer = question, answer
    m.phase = "asking"
    return true
end

function Match.reveal(m)
    if m.phase ~= "asking" then return false end
    m.phase = "revealed"
    return true
end

-- Gives the point to player i (nil = nobody), once per question. Ends the
-- match after the last question.
function Match.give(m, i)
    if m.phase ~= "revealed" then return false end
    if i then Party.award(m.scores, i, 1) end
    m.phase = "done"
    if m.scores.round >= m.questions then m.finished = true end
    return true
end

-- "7 + 5 = ?" → "7 + 5 = 12".
function Match.answerText(question, answer)
    if not question then return "" end
    local s, n = question:gsub("%?%s*$", tostring(answer))
    if n == 0 then s = question .. " " .. tostring(answer) end
    return s
end

function Match.serialize(m)
    return {
        scores    = Party.copyScores(m.scores),
        questions = m.questions,
        question  = m.question,
        answer    = m.answer,
        phase     = m.phase,
        finished  = m.finished,
    }
end

function Match.restore(t)
    if type(t) ~= "table" then return nil end
    local scores = Party.restoreScores(t.scores)
    local n = tonumber(t.questions)
    if not scores or not n or n < 1 or scores.round > n then return nil end
    local phase = t.phase
    if phase ~= "asking" and phase ~= "revealed" and phase ~= "done" then return nil end
    if phase ~= "done" and (type(t.question) ~= "string" or t.answer == nil) then return nil end
    return {
        scores    = scores,
        questions = n,
        question  = t.question,
        answer    = t.answer,
        phase     = phase,
        finished  = t.finished == true,
    }
end

return Match
