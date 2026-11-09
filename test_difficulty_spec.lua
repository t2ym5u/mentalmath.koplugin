local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

-- Difficulty guarantees: each level asks only its own operations, with
-- operands and answers in its band; the levels are ordered (more operations,
-- bigger numbers on average); a seed always asks the same questions, and
-- the questions never depend on the clock.
local LEVELS = { "easy", "medium", "hard" }
local QUESTIONS = 300

local PLUS, MINUS, TIMES, DIVIDE = "+", "\xe2\x88\x92", "\xc3\x97", "\xc3\xb7"

-- Per level: allowed operations and, for each, the band of each operand.
local BANDS = {
    easy = {
        [PLUS]  = { { 1, 9 }, { 1, 9 } },
        [MINUS] = { { 2, 18 }, { 1, 17 } },
    },
    medium = {
        [PLUS]  = { { 10, 50 }, { 1, 20 } },
        [MINUS] = { { 11, 60 }, { 1, 20 } },
        [TIMES] = { { 2, 9 }, { 2, 9 } },
    },
    hard = {
        [PLUS]   = { { 11, 99 }, { 11, 99 } },
        [MINUS]  = { { 20, 99 }, { 10, 98 } },
        [TIMES]  = { { 2, 12 }, { 2, 12 } },
        [DIVIDE] = { { 4, 81 }, { 2, 9 } },
    },
}

local function parse(q)
    local a, op, b = q:match("^(%d+) (%S+) (%d+) = %?$")
    return tonumber(a), op, tonumber(b)
end

-- Runs fn with os.clock/os.time wrapped; returns how often they were read.
local function clockReads(fn)
    local clock, time = os.clock, os.time
    local reads = 0
    os.clock = function() reads = reads + 1; return clock() end
    os.time = function(...) reads = reads + 1; return time(...) end
    local ok, err = pcall(fn)
    os.clock, os.time = clock, time
    assert(ok, err)
    return reads
end

describe("Mental math difficulty", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    it("hard-difficulty division always yields an exact integer answer", function()
        math.randomseed(3)
        local b = Board:new({ difficulty = "hard" })
        for _ = 1, 30 do
            b:generate()
            assert.are.equal(math.floor(b.answer), b.answer)
        end
    end)

    for _, level in ipairs(LEVELS) do
        it(level .. ": only its operations, operands in band, the answer right and positive", function()
            math.randomseed(17)
            local b = Board:new({ difficulty = level })
            local seen = {}
            for _ = 1, QUESTIONS do
                b:generate()
                local x, op, y = parse(b.question)
                assert.is_truthy(x, b.question)
                local band = BANDS[level][op]
                assert.is_truthy(band, level .. " asked " .. b.question)
                seen[op] = true
                assert.is_true(x >= band[1][1] and x <= band[1][2], b.question)
                assert.is_true(y >= band[2][1] and y <= band[2][2], b.question)
                local want = (op == PLUS and x + y) or (op == MINUS and x - y)
                    or (op == TIMES and x * y) or x / y
                assert.are.equal(want, b.answer, b.question)
                assert.is_true(b.answer >= 1, b.question)
            end
            -- every operation of the level does come up
            for op in pairs(BANDS[level]) do assert.is_true(seen[op], level .. " never asked " .. op) end
        end)
    end

    it("the levels are ordered: more operations, bigger operands on average", function()
        local prev_ops, prev_size = 0, 0
        for _, level in ipairs(LEVELS) do
            local ops = 0
            for _ in pairs(BANDS[level]) do ops = ops + 1 end
            math.randomseed(29)
            local b = Board:new({ difficulty = level })
            local size = 0
            for _ = 1, QUESTIONS do
                b:generate()
                local x, _, y = parse(b.question)
                size = size + math.max(x, y)
            end
            size = size / QUESTIONS
            assert.is_true(ops > prev_ops, level)
            assert.is_true(size > prev_size, ("%s: mean operand %.1f"):format(level, size))
            prev_ops, prev_size = ops, size
        end
    end)

    it("the same seed asks the same questions", function()
        for _, level in ipairs(LEVELS) do
            local runs = {}
            for k = 1, 2 do
                math.randomseed(8)
                local b = Board:new({ difficulty = level })
                local t = {}
                for i = 1, 20 do
                    b:generate()
                    t[i] = b.question .. "|" .. table.concat(b.options, ",")
                end
                runs[k] = t
            end
            assert.are.same(runs[1], runs[2])
        end
    end)

    it("questions never read the clock", function()
        for _, level in ipairs(LEVELS) do
            local reads = clockReads(function()
                local b = Board:new({ difficulty = level })
                for _ = 1, 20 do b:generate() end
            end)
            assert.are.equal(0, reads, level)
        end
    end)
end)
