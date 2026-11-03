-- Spec for the multiplayer "buzzer" mode: questions, points, save/restore.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. DIR .. "common/?.lua;" .. package.path

package.loaded["i18n"] = function(s) return s end
package.loaded["ffi/util"] = { template = function(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end }

local Match = require("match")

describe("mentalmath multiplayer", function()
    it("asks, reveals, gives the point once", function()
        local m = Match.new({ "A", "B", "C" }, 3)
        assert.is_false(Match.reveal(m))            -- nothing asked yet
        assert.is_true(Match.ask(m, "2 + 3 = ?", 5))
        assert.are.equal(1, Match.current(m))
        assert.is_false(Match.give(m, 1))           -- not revealed yet
        assert.is_true(Match.reveal(m))
        assert.is_true(Match.give(m, 2))
        assert.is_false(Match.give(m, 2))
        assert.are.same({ 0, 1, 0 }, m.scores.points)
    end)

    it("nobody scores nothing; the match ends after N questions", function()
        local m = Match.new({ "A", "B" }, 2)
        Match.ask(m, "1 + 1 = ?", 2); Match.reveal(m); Match.give(m, nil)
        assert.is_false(m.finished)
        Match.ask(m, "2 × 2 = ?", 4); Match.reveal(m); Match.give(m, 1)
        assert.is_true(m.finished)
        assert.is_false(Match.ask(m, "3 + 3 = ?", 6))
        assert.are.same({ 1, 0 }, m.scores.points)
    end)

    it("writes the answer into the question", function()
        assert.are.equal("7 + 5 = 12", Match.answerText("7 + 5 = ?", 12))
        assert.are.equal("", Match.answerText(nil, 3))
    end)

    it("survives save and restore, and refuses broken saves", function()
        local m = Match.new({ "A", "B" }, 10)
        Match.ask(m, "9 − 4 = ?", 5); Match.reveal(m)
        local t = Match.restore(Match.serialize(m))
        assert.are.equal("revealed", t.phase)
        assert.are.equal(5, t.answer)
        assert.are.equal(1, t.scores.round)
        assert.is_true(Match.give(t, 1))
        assert.is_nil(Match.restore({ scores = m.scores, questions = 10, phase = "asking" }))
        assert.is_nil(Match.restore({ scores = m.scores, questions = 0, phase = "done" }))
        assert.is_nil(Match.restore(42))
    end)
end)
