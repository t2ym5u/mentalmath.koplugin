local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("CalcBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    describe("generate", function()
        it("produces a question whose correct answer is among the 4 options", function()
            math.randomseed(42)
            local b = Board:new()
            b:generate()
            assert.is_true(#b.question > 0)
            local found = false
            for _, opt in ipairs(b.options) do
                if opt == b.answer then found = true end
            end
            assert.is_true(found)
            assert.are.equal(4, #b.options)
        end)

        it("options contain no duplicates", function()
            math.randomseed(7)
            local b = Board:new()
            for _ = 1, 20 do
                b:generate()
                local seen = {}
                for _, opt in ipairs(b.options) do
                    assert.is_nil(seen[opt])
                    seen[opt] = true
                end
            end
        end)
    end)

    describe("wrong answers", function()
        -- With random offsets the right answer was the only choice ending in
        -- its digit in ~73% of questions; the units digit gave it away.
        it("rarely leave the right answer alone with its last digit", function()
            for _, diff in ipairs({ "easy", "medium", "hard" }) do
                math.randomseed(11)
                local b = Board:new({ difficulty = diff })
                local n, alone = 0, 0
                for _ = 1, 2000 do
                    b:generate()
                    if b.answer >= 10 then
                        n = n + 1
                        local same = 0
                        for _, o in ipairs(b.options) do
                            if o ~= b.answer and o % 10 == b.answer % 10 then same = same + 1 end
                        end
                        if same == 0 then alone = alone + 1 end
                    end
                end
                assert.is_true(alone / n <= 0.30, diff .. ": " .. alone / n)
            end
        end)

        it("put the right answer anywhere in the order", function()
            math.randomseed(5)
            local b = Board:new({ difficulty = "medium" })
            local ranks = { 0, 0, 0, 0 }
            for _ = 1, 2000 do
                b:generate()
                local r = 1
                for _, o in ipairs(b.options) do if o < b.answer then r = r + 1 end end
                ranks[r] = ranks[r] + 1
            end
            for r = 1, 4 do assert.is_true(ranks[r] >= 300, "rank " .. r .. ": " .. ranks[r]) end
        end)

        it("are never negative and always four distinct numbers", function()
            for _, diff in ipairs({ "easy", "medium", "hard" }) do
                math.randomseed(2)
                local b = Board:new({ difficulty = diff })
                for _ = 1, 500 do
                    b:generate()
                    assert.are.equal(4, #b.options)
                    local seen = {}
                    for _, o in ipairs(b.options) do
                        assert.is_true(o >= 0)
                        assert.is_nil(seen[o]); seen[o] = true
                    end
                end
            end
        end)

        it("stay close to the answer (slips, not random numbers)", function()
            math.randomseed(9)
            local b = Board:new({ difficulty = "hard" })
            for _ = 1, 500 do
                b:generate()
                for _, o in ipairs(b.options) do
                    -- a tens slip of a times-table neighbour: at most 12 + 10 + 12
                    assert.is_true(math.abs(o - b.answer) <= 34)
                end
            end
        end)
    end)

    describe("rules text", function()
        it("no longer claims the difficulty adapts", function()
            local f = assert(io.open(DIR .. "screen.lua"))
            local src = f:read("*a"); f:close()
            assert.falsy(src:find("Difficulty increases", 1, true))
            assert.falsy(src:find("difficulté augmente", 1, true))
        end)
    end)

    describe("checkAnswer", function()
        it("marks a correct answer, increments correct/streak/total", function()
            local b = Board:new()
            b:generate()
            assert.is_true(b:checkAnswer(b.answer))
            assert.are.equal(1, b.total)
            assert.are.equal(1, b.correct)
            assert.are.equal(1, b.streak)
            assert.is_true(b.last_ok)
        end)

        it("resets streak on a wrong answer", function()
            local b = Board:new()
            b:generate()
            b:checkAnswer(b.answer)
            b:generate()
            local wrong = b.answer + 1000  -- guaranteed not to equal a fresh answer
            assert.is_false(b:checkAnswer(wrong))
            assert.are.equal(0, b.streak)
            assert.is_false(b.last_ok)
            assert.are.equal(2, b.total)
        end)
    end)

    describe("resetStats", function()
        it("clears total/correct/streak but keeps difficulty", function()
            local b = Board:new({ difficulty = "hard" })
            b:generate()
            b:checkAnswer(b.answer)
            b:resetStats()
            assert.are.equal(0, b.total)
            assert.are.equal(0, b.correct)
            assert.are.equal(0, b.streak)
            assert.are.equal("hard", b.difficulty)
        end)
    end)

    describe("serialize / load", function()
        it("round-trips difficulty and score totals", function()
            local b = Board:new({ difficulty = "medium" })
            b:generate()
            b:checkAnswer(b.answer)
            local data = b:serialize()

            local b2 = Board:new()
            assert.is_true(b2:load(data))
            assert.are.equal("medium", b2.difficulty)
            assert.are.equal(b.total, b2.total)
            assert.are.equal(b.correct, b2.correct)
        end)

        it("load returns false for non-table data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
        end)
    end)
end)
