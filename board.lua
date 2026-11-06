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
    local q, a, near = self:_makeQuestion()
    self.question = q
    self.answer   = a
    self.options  = self:_makeOptions(a, near)
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
            return string.format("%d \xc3\x97 %d = ?", a, b), a * b,
                { a * b + a, a * b - a, a * b + b, a * b - b }
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
            return string.format("%d \xc3\x97 %d = ?", a, b), a * b,
                { a * b + a, a * b - a, a * b + b, a * b - b }
        else
            -- Exact division
            local divisor  = math.random(2, 9)
            local quotient = math.random(2, 9)
            return string.format("%d \xc3\xb7 %d = ?", divisor * quotient, divisor), quotient
        end
    end
end

-- Build 4 plausible choices (one correct, three wrong).
--
-- Wrong answers look like real slips: a tens error (+-10, same last digit),
-- an off-by-one or two, and for a product a neighbouring line of the times
-- table (+-a or +-b). They used to be random offsets of 1 to 20, so in about
-- 3 questions out of 4 the right answer was the only choice ending in its
-- digit: working out the units alone gave it away.
--
-- Now the four choices follow a shape, drawn first and only then shifted so
-- that one of its four values -- at random -- is the right answer:
--   * 60%: two pairs {x, x+-10} and {y, y+-10}, y a near miss of x;
--   * 40%: one pair {x, x+-10} and two near misses of x.
-- (A one-digit answer gets three near misses of up to 3 instead.)
-- Every value of a shape is a slip away from the others, so whichever one is
-- right, the rest still look like mistakes, and the right answer sits
-- anywhere in the order. The units digit picks out the answer only when it
-- is one of the two loose near misses (about 1 question in 5).
--
-- `near` (optional) lists more near misses of `correct` (times-table
-- neighbours), used as offsets like +-1 and +-2.
local function shuffled(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local TWO_PAIRS_IN_10 = 6
local SHAPE_TRIES     = 30

function CalcBoard:_makeOptions(correct, near)
    local steps = { 1, -1, 2, -2 }
    for _, w in ipairs(near or {}) do
        local k = w - correct
        if k ~= 0 and k % 10 ~= 0 then steps[#steps + 1] = k end
    end
    local function tens() return math.random(2) == 1 and 10 or -10 end

    for _ = 1, SHAPE_TRIES do
        local shape
        local k1 = steps[math.random(#steps)]
        if correct < 10 then
            -- A one-digit answer: a tens slip would be far-fetched (and could
            -- only go up, always leaving the answer lowest), so three near
            -- misses of up to 3.
            local small = shuffled({ 1, -1, 2, -2, 3, -3 })
            shape = { 0, small[1], small[2], small[3] }
        elseif math.random(10) <= TWO_PAIRS_IN_10 then
            shape = { 0, tens(), k1, k1 + tens() }
        else
            local k2 = steps[math.random(#steps)]
            shape = { 0, tens(), k1, k2 }
        end
        local base = correct - shape[math.random(4)]
        local seen, ok, out = {}, true, {}
        for i, v in ipairs(shape) do
            local w = base + v
            if w < 0 or seen[w] then ok = false; break end
            seen[w] = true
            out[i] = w
        end
        if ok then return shuffled(out) end
    end

    -- Small answers may fit no shape: any offset up to 20.
    local used, choices = { [correct] = true }, { correct }
    local offsets = {}
    for d = 1, 20 do
        offsets[#offsets + 1] =  d
        offsets[#offsets + 1] = -d
    end
    for _, d in ipairs(shuffled(offsets)) do
        local w = correct + d
        if #choices < 4 and w >= 0 and not used[w] then
            used[w] = true
            choices[#choices + 1] = w
        end
    end
    return shuffled(choices)
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
