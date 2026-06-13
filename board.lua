-- ---------------------------------------------------------------------------
-- CalcBoard — game logic for Calcul Mental (mental arithmetic quiz)
--
-- Generates arithmetic questions with 4 multiple-choice answers.
-- Tracks score (correct / total) and current streak.
-- ---------------------------------------------------------------------------

local CalcBoard = {}
CalcBoard.__index = CalcBoard

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

function CalcBoard:new(opts)
    opts = opts or {}
    local o = setmetatable({}, self)
    o.difficulty = opts.difficulty or "easy"
    o.total      = 0
    o.correct    = 0
    o.streak     = 0
    o.question   = nil
    o.answer     = nil
    o.options    = {}    -- 4 integer choices, shuffled
    o.last_ok    = nil   -- true/false/nil after last answer
    o.status     = "playing"
    return o
end

-- ---------------------------------------------------------------------------
-- Generate a new question
-- ---------------------------------------------------------------------------

function CalcBoard:generate()
    self.last_ok = nil
    local q, a  = self:_makeQuestion()
    self.question = q
    self.answer   = a
    self.options  = self:_makeOptions(a)
    self.status   = "playing"
end

function CalcBoard:_makeQuestion()
    local diff = self.difficulty

    if diff == "easy" then
        local op = math.random(2)
        if op == 1 then
            local a = math.random(1, 9)
            local b = math.random(1, 9)
            return string.format("%d + %d = ?", a, b), a + b
        else
            local a = math.random(2, 18)
            local b = math.random(1, a - 1)
            return string.format("%d \xe2\x88\x92 %d = ?", a, b), a - b
        end

    elseif diff == "medium" then
        local op = math.random(3)
        if op == 1 then
            local a = math.random(10, 50)
            local b = math.random(1, 20)
            return string.format("%d + %d = ?", a, b), a + b
        elseif op == 2 then
            local a = math.random(11, 60)
            local b = math.random(1, math.min(a - 1, 20))
            return string.format("%d \xe2\x88\x92 %d = ?", a, b), a - b
        else
            local a = math.random(2, 9)
            local b = math.random(2, 9)
            return string.format("%d \xc3\x97 %d = ?", a, b), a * b
        end

    else  -- hard
        local op = math.random(4)
        if op == 1 then
            local a = math.random(11, 99)
            local b = math.random(11, 99)
            return string.format("%d + %d = ?", a, b), a + b
        elseif op == 2 then
            local a = math.random(20, 99)
            local b = math.random(10, a - 1)
            return string.format("%d \xe2\x88\x92 %d = ?", a, b), a - b
        elseif op == 3 then
            local a = math.random(2, 12)
            local b = math.random(2, 12)
            return string.format("%d \xc3\x97 %d = ?", a, b), a * b
        else
            -- Exact division
            local divisor  = math.random(2, 9)
            local quotient = math.random(2, 9)
            return string.format("%d \xc3\xb7 %d = ?", divisor * quotient, divisor), quotient
        end
    end
end

-- Build 4 plausible choices (one correct, three wrong)
function CalcBoard:_makeOptions(correct)
    local used    = { [correct] = true }
    local choices = { correct }

    -- Pool of offsets to try, from close to far
    local offsets = {}
    for d = 1, 20 do
        offsets[#offsets + 1] =  d
        offsets[#offsets + 1] = -d
    end
    -- Shuffle offsets
    for i = #offsets, 2, -1 do
        local j = math.random(i)
        offsets[i], offsets[j] = offsets[j], offsets[i]
    end

    for _, d in ipairs(offsets) do
        if #choices >= 4 then break end
        local w = correct + d
        if w >= 0 and not used[w] then
            used[w] = true
            choices[#choices + 1] = w
        end
    end

    -- Shuffle final choices so correct is not always first
    for i = #choices, 2, -1 do
        local j = math.random(i)
        choices[i], choices[j] = choices[j], choices[i]
    end
    return choices
end

-- ---------------------------------------------------------------------------
-- Answer checking
-- ---------------------------------------------------------------------------

-- Returns true if correct, false otherwise.
function CalcBoard:checkAnswer(choice)
    self.total = self.total + 1
    if choice == self.answer then
        self.correct  = self.correct + 1
        self.streak   = self.streak + 1
        self.last_ok  = true
        return true
    else
        self.streak  = 0
        self.last_ok = false
        return false
    end
end

-- ---------------------------------------------------------------------------
-- Reset session stats (keep difficulty)
-- ---------------------------------------------------------------------------

function CalcBoard:resetStats()
    self.total   = 0
    self.correct = 0
    self.streak  = 0
    self.last_ok = nil
end

-- ---------------------------------------------------------------------------
-- Serialization (save/restore between sessions)
-- ---------------------------------------------------------------------------

function CalcBoard:serialize()
    return {
        difficulty = self.difficulty,
        total      = self.total,
        correct    = self.correct,
    }
end

function CalcBoard:load(data)
    if type(data) ~= "table" then return false end
    if data.difficulty then self.difficulty = data.difficulty end
    self.total   = tonumber(data.total)   or 0
    self.correct = tonumber(data.correct) or 0
    self.streak  = 0
    self.last_ok = nil
    return true
end

return CalcBoard
