---@diagnostic disable: undefined-global

local util = require("gptmodels.util")
local stub = require('luassert.stub')
local assert = require("luassert")

describe("util", function()
  describe("contains_line", function()
    assert(util.contains_line({ "has", "also" }, "has"))
    assert.False(util.contains_line({ "doesnt" }, "has"))
  end)

  describe("guid", function()
    it("never repeats", function()
      local guids = {}
      for _ = 1, 1000 do
        guids[util.guid()] = true
      end

      local count = 0
      for _ in pairs(guids) do
        count = count + 1
      end

      assert.equal(1000, count)
    end)
  end)

  describe("log", function()
    it("works", function()
      local io_open_stub = stub(io, "open")

      ---@type string[]
      local writes = {}
      local num_flushes = 0
      local num_closes = 0

      local log_file = {
        -- _ is because write is a _method_, log_file:write, so it gets self arg
        write = function(_, arg1, arg2)
          table.insert(writes, arg1)
          table.insert(writes, arg2)
        end,
        flush = function()
          num_flushes = num_flushes + 1
        end,
        close = function()
          num_closes = num_closes + 1
        end
      }

      io_open_stub.returns(log_file)

      util.log(1, 2, 3, 4, 5)

      assert.same({ "1\n", "2\n", "3\n", "4\n", "5\n", }, writes)
      assert.equal(1, num_flushes)
      assert.equal(1, num_closes)
    end)
  end)

  describe("merge_tables", function()
    it("merges hash style tables", function()
      local a = { a = true }
      local b = { b = true }
      local c = util.merge_tables(a, b)
      assert.same(c, { a = true, b = true })
    end)

    it("merges array style tables", function()
      local a = { true }
      local b = { false }
      local c = util.merge_tables(a, b)
      assert.same(c, { true, false })
    end)

    it("merges combo style tables", function()
      local a = { a = true }
      local b = { false }
      local c = util.merge_tables(a, b)
      assert.same(c, { a = true, false })
    end)

    it("merges combo style tables", function()
      local a = { a = true }
      local b = { false }
      local c = util.merge_tables(a, b)
      assert.same(c, { a = true, false })
    end)

    it("does not overwrite arguments", function()
      local a = { a = true }
      local b = { b = true }
      util.merge_tables(a, b)
      assert.same(a, { a = true })
      assert.same(b, { b = true })
    end)
  end)

  describe("get_visual_selection", function()
    it("returns the correctly shaped object", function()
      local res = util.get_visual_selection()
      assert.is_true(res.start_line ~= nil)
      assert.is_true(res.end_line ~= nil)
      assert.is_true(res.start_column ~= nil)
      assert.is_true(res.end_column ~= nil)
      assert.is_true(res.text ~= nil)
    end)
  end)
end)
