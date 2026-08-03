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

        it("hard-difficulty division always yields an exact integer answer", function()
            math.randomseed(3)
            local b = Board:new({ difficulty = "hard" })
            for _ = 1, 30 do
                b:generate()
                assert.are.equal(math.floor(b.answer), b.answer)
            end
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
