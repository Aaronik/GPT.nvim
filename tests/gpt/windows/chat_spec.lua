---@diagnostic disable: undefined-global

require('gpt.types')
local util = require("gpt.util")
local assert = require("luassert")
local chat_window = require('gpt.windows.chat')
local stub = require('luassert.stub')
local spy = require('luassert.spy')
local llm = require('gpt.llm')
local cmd = require('gpt.cmd')
local Store = require('gpt.store')

local skip = pending

describe("The Chat window", function()
  before_each(function()
    -- Set current window dims, otherwise it defaults to 0 and nui.layout complains about not having a pos integer height
    vim.api.nvim_win_set_height(0, 100)
    vim.api.nvim_win_set_width(0, 100)

    -- clear cmd history, lest it get remembered and bleed across tests
    vim.fn.histdel('cmd')

    -- stubbing cmd.exec prevents the llm call from happening
    stub(cmd, "exec")

    Store:clear()
  end)

  it("returns buffer numbers and winids", function()
    local chat = chat_window.build_and_mount()
    assert.is_not.equal(chat.input, nil)
    assert.is_not.equal(chat.chat, nil)
  end)

  skip("opens in input mode", function()
    chat_window.build_and_mount()
    vim.api.nvim_feedkeys('xhello', 'mtx', true)
    -- For some reason, the first letter is always trimmed off. But if it's not in insert mode, the line will be empty ""
    assert.same(vim.api.nvim_get_current_line(), 'hello')
  end)

  it("puts selected text into input buffer and puts newline under it", function()
    local chat = chat_window.build_and_mount({ "selected text" })
    local input_lines = vim.api.nvim_buf_get_lines(chat.input.bufnr, 0, -1, true)
    assert.same({ "selected text", "" }, input_lines)
  end)

  it("opens with last chat", function()
    local content = "window should open with this content populated"
    Store.chat.chat:append({ role = "assistant", content = content })

    local chat = chat_window.build_and_mount()
    local chat_bufnr = chat.chat.bufnr

    local lines = vim.api.nvim_buf_get_lines(chat_bufnr, 0, -1, true)
    assert.equal(content, lines[1])
  end)

  it("clears all windows and kills job when opened with selected text", function()
    -- First, open a window and add some stuff
    local first_given_lines = { "first" }
    local chat = chat_window.build_and_mount(first_given_lines) -- populate input a bit

    local die_called = false

    local llm_stub = stub(llm, "chat")
    llm_stub.returns({
      die = function()
        die_called = true
      end,
      done = function()
        return die_called
      end
    })

    local keys = vim.api.nvim_replace_termcodes('xhello<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false) -- populate input, fire request

    ---@type MakeChatRequestArgs
    local args = llm_stub.calls[1].refs[1]

    args.on_read(nil, { role = "assistant", content = "some content" }) -- populate chat pane

    -- close the window
    keys = vim.api.nvim_replace_termcodes(':q<CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false) -- populate input, fire request

    local second_given_lines = { "second" }

    chat = chat_window.build_and_mount(second_given_lines)

    assert(die_called)

    local chat_lines = vim.api.nvim_buf_get_lines(chat.chat.bufnr, 0, -1, true)
    local input_lines = vim.api.nvim_buf_get_lines(chat.input.bufnr, 0, -1, true)
    assert.same({ "" }, chat_lines)
    assert.same({ "second", "" }, input_lines)
  end)

  it("shifts through windows on <Tab>", function()
    local chat = chat_window.build_and_mount()
    local input_bufnr = chat.input.bufnr
    local chat_bufnr = chat.chat.bufnr

    local input_win = vim.fn.bufwinid(input_bufnr)
    local chat_win = vim.fn.bufwinid(chat_bufnr)

    local esc = vim.api.nvim_replace_termcodes('<Esc>', true, true, true)
    local tab = vim.api.nvim_replace_termcodes("<Tab>", true, true, true)

    vim.api.nvim_feedkeys(esc, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), input_win)
    vim.api.nvim_feedkeys(tab, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), chat_win)
    vim.api.nvim_feedkeys(tab, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), input_win)
  end)

  it("shifts through windows on <S-Tab>", function()
    local chat = chat_window.build_and_mount()
    local input_bufnr = chat.input.bufnr
    local chat_bufnr = chat.chat.bufnr

    local input_win = vim.fn.bufwinid(input_bufnr)
    local chat_win = vim.fn.bufwinid(chat_bufnr)

    local esc = vim.api.nvim_replace_termcodes('<Esc>', true, true, true)
    local tab = vim.api.nvim_replace_termcodes("<S-Tab>", true, true, true)

    vim.api.nvim_feedkeys(esc, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), input_win)
    vim.api.nvim_feedkeys(tab, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), chat_win)
    vim.api.nvim_feedkeys(tab, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), input_win)
  end)

  it("Removes text from input and puts it in chat on <CR>", function()
    local chat = chat_window.build_and_mount()
    local input_bufnr = chat.input.bufnr
    local chat_bufnr = chat.chat.bufnr

    local keys = vim.api.nvim_replace_termcodes('ihello<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    local chat_lines = vim.api.nvim_buf_get_lines(chat_bufnr, 0, -1, true)

    -- ensure hello is one of the lines in chat buf
    assert.is_true(util.contains_line(chat_lines, "hello"))

    -- ensure input is empty
    local input_lines = vim.api.nvim_buf_get_lines(input_bufnr, 0, -1, true)
    assert.same(input_lines, { "" })
  end)

  it("Places llm response into chat window", function()
    local chat = chat_window.build_and_mount()
    local input_bufnr = chat.input.bufnr
    local chat_bufnr = chat.chat.bufnr

    -- stub llm call
    local s = stub(llm, "chat")

    vim.api.nvim_buf_set_lines(input_bufnr, 0, -1, true, { "hello" })

    -- make call to llm stub
    local keys = vim.api.nvim_replace_termcodes('<CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    -- grab the given callback
    ---@type MakeChatRequestArgs
    local args = s.calls[1].refs[1]

    -- simulate llm responding
    args.on_read(nil, { role = "assistant", content = "response text1\nresponse text2" })

    -- Now the chat buffer should have all the things
    local chat_lines = vim.api.nvim_buf_get_lines(chat_bufnr, 0, -1, true)

    assert(util.contains_line(chat_lines, "hello"))
    assert(util.contains_line(chat_lines, "response text1"))
    assert(util.contains_line(chat_lines, "response text2"))
  end)

  it("clears all windows on <C-n>", function()
    local chat = chat_window.build_and_mount()

    -- Populate windows with some content
    vim.api.nvim_buf_set_lines(chat.input.bufnr, 0, -1, true, { "input content" })
    vim.api.nvim_buf_set_lines(chat.chat.bufnr, 0, -1, true, { "chat content" })
    Store.chat:append_file("docs/gpt.txt")

    -- Press <C-n>
    local keys = vim.api.nvim_replace_termcodes("<C-n>", true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)

    -- Assert all windows are cleared
    assert.same({ '' }, vim.api.nvim_buf_get_lines(chat.input.bufnr, 0, -1, true))
    assert.same({ '' }, vim.api.nvim_buf_get_lines(chat.chat.bufnr, 0, -1, true))

    -- And the store of included files
    assert.same({}, Store.chat:get_files())
  end)

  it("cycles through available models with <C-j>", function()
    chat_window.build_and_mount()

    local snapshot = assert:snapshot()

    local store_spy = spy.on(Store, "set_llm")

    -- Press <C-j>
    local ctrl_j = vim.api.nvim_replace_termcodes("<C-j>", true, true, true)
    vim.api.nvim_feedkeys(ctrl_j, 'mtx', true)

    assert.spy(store_spy).was_called(1)
    local first_args = store_spy.calls[1].refs
    assert.equal(type(first_args[2]), "string")
    assert.equal(type(first_args[3]), "string")

    -- Press <C-j> again
    vim.api.nvim_feedkeys(ctrl_j, 'mtx', true)

    assert.spy(store_spy).was_called(2)
    local second_args = store_spy.calls[2].refs
    assert.equal(type(second_args[2]), "string")
    assert.equal(type(second_args[3]), "string")

    -- Make sure the model is different, which it definitely should be.
    -- The provider might be the same.
    assert.is_not.equal(first_args[3], second_args[3])

    snapshot:revert()
  end)

  it("cycles through available models with <C-k>", function()
    chat_window.build_and_mount()

    local snapshot = assert:snapshot()

    local store_spy = spy.on(Store, "set_llm")

    -- Press <C-k>
    local ctrl_k = vim.api.nvim_replace_termcodes("<C-k>", true, true, true)
    vim.api.nvim_feedkeys(ctrl_k, 'mtx', true)

    assert.spy(store_spy).was_called(1)
    local first_args = store_spy.calls[1].refs
    assert.equal(type(first_args[2]), "string")
    assert.equal(type(first_args[3]), "string")

    -- Press <C-k> again
    vim.api.nvim_feedkeys(ctrl_k, 'mtx', true)

    assert.spy(store_spy).was_called(2)
    local second_args = store_spy.calls[2].refs
    assert.equal(type(second_args[2]), "string")
    assert.equal(type(second_args[3]), "string")

    -- Make sure the model is different, which it definitely should be.
    -- The provider might be the same.
    assert.is_not.equal(first_args[3], second_args[3])

    snapshot:revert()
  end)

  it("kills active job on <C-c>", function()
    chat_window.build_and_mount()
    local s = stub(llm, "chat")
    local die_called = false

    s.returns({
      die = function()
        die_called = true
      end
    })

    -- Make a request to start a job
    local keys = vim.api.nvim_replace_termcodes('xhello<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    -- press ctrl-n
    keys = vim.api.nvim_replace_termcodes('<C-c>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    assert.is_true(die_called)
  end)

  it("includes files on <C-f> and clears them on <C-g>", function()
    chat_window.build_and_mount()

    -- I'm only stubbing this because it's so hard to test. One time out of hundreds
    -- I was able to get the test to reflect a picked file. I don't know if there's some
    -- async magic or what but I can't make it work. Tried vim.wait forever.
    local find_files = stub(require('telescope.builtin'), "find_files")

    -- For down the line of this crazy stubbing exercise
    local get_selected_entry = stub(require('telescope.actions.state'), "get_selected_entry")
    get_selected_entry.returns({ "README.md", index = 1 }) -- typical response

    -- And just make sure there are no closing errors
    stub(require('telescope.actions'), "close")

    -- Press ctl-f to open the telescope picker
    local ctrl_f = vim.api.nvim_replace_termcodes('<C-f>', true, true, true)
    vim.api.nvim_feedkeys(ctrl_f, 'mtx', false)

    -- Press enter to select the first file, was Makefile in testing
    local cr = vim.api.nvim_replace_termcodes('<CR>', true, true, true)
    vim.api.nvim_feedkeys(cr, 'mtx', false)

    -- Simulate finding a file
    assert.stub(find_files).was_called(1)
    local attach_mappings = find_files.calls[1].refs[1].attach_mappings
    local map = stub()
    map.invokes(function(_, _, cb)
      cb(9999) -- this will call get_selected_entry internally
    end)
    attach_mappings(nil, map)

    -- Now we'll check what was given to llm.chat
    local chat_stub = stub(llm, "chat")
    vim.api.nvim_feedkeys(cr, 'mtx', false)

    ---@type MakeChatRequestArgs
    local args = chat_stub.calls[1].refs[1]

    -- Does the request now contain a system message with the file
    local contains_system_with_file = false
    for _, message in ipairs(args.llm.messages) do
      if message.role == "system" and message.content.match(message.content, "README.md") then
        contains_system_with_file = true
      end
    end
    assert.True(contains_system_with_file)

    -- Now we'll make sure C-g clears the files
    local ctrl_g = vim.api.nvim_replace_termcodes('<C-g>', true, true, true)
    vim.api.nvim_feedkeys(ctrl_g, 'mtx', false)
    vim.api.nvim_feedkeys(cr, 'mtx', false)

    ---@type MakeChatRequestArgs
    args = chat_stub.calls[2].refs[1]

    -- Does the request now contain a system message with the file
    contains_system_with_file = false
    for _, message in ipairs(args.llm.messages) do
      if message.role == "system" and message.content.match(message.content, "README.md") then
        contains_system_with_file = true
      end
    end
    assert.False(contains_system_with_file)
  end)

  it("closes the window on q", function()
    local chat = chat_window.build_and_mount()

    -- Send a request
    local q_key = vim.api.nvim_replace_termcodes("q", true, true, true)
    vim.api.nvim_feedkeys(q_key, 'mtx', true)

    -- assert window was closed
    assert.is_nil(chat.input.winid)
    assert.is_nil(chat.input.bufnr)
  end)

  it("saves input text on InsertLeave and prepopulates on reopen", function()
    local initial_input = "some initial input"
    local chat = chat_window.build_and_mount()

    -- Enter insert mode
    local keys = vim.api.nvim_replace_termcodes("i" .. initial_input, true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)

    -- <Esc> to trigger save
    keys = vim.api.nvim_replace_termcodes("<Esc>", true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)

    -- Close the window with :q
    keys = vim.api.nvim_replace_termcodes(":q<CR>", true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)

    -- Reopen the window
    chat = chat_window.build_and_mount()

    local input_lines = vim.api.nvim_buf_get_lines(chat.input.bufnr, 0, -1, true)

    assert.same({ initial_input }, input_lines)
  end)

  it("finishes jobs in the background when closed", function()
    chat_window.build_and_mount()
    local s = stub(llm, "chat")
    local die_called = false

    s.returns({
      die = function()
        die_called = true
      end
    })

    -- Make a request to start a job
    local keys = vim.api.nvim_replace_termcodes('ihello<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    -- quit with :q
    keys = vim.api.nvim_replace_termcodes('<Esc>:q<CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    assert.is_not.True(die_called)

    -- -- simulate hint of wait time for the nui windows to close
    -- -- This leads to errors about invalid windows.
    -- -- Might be nui issue, see code_spec
    -- vim.wait(10)

    ---@type MakeChatRequestArgs
    local args = s.calls[1].refs[1]

    args.on_read(nil, { role = "assistant", content = "response to be saved in background" })

    -- Open up and ensure it's there now
    local chat = chat_window.build_and_mount()
    assert(util.contains_line(vim.api.nvim_buf_get_lines(chat.chat.bufnr, 0, -1, true),
      "response to be saved in background"))


    -- More reponse to still reopen window
    args.on_read(nil, { role = "assistant", content = "\nadditional response" })

    -- Gets that response without reopening
    local chat_lines = vim.api.nvim_buf_get_lines(chat.chat.bufnr, 0, -1, true)
    assert(util.contains_line(chat_lines, "response to be saved in background"))
    assert(util.contains_line(chat_lines, "additional response"))
  end)

  it("automatically scrolls chat window when user is not in it", function()
    local chat = chat_window.build_and_mount()

    local llm_stub = stub(llm, "chat")

    local keys = vim.api.nvim_replace_termcodes('<CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    ---@type MakeChatRequestArgs
    local args = llm_stub.calls[1].refs[1]

    local long_content = ""
    for _ = 1, 1000, 1 do
      long_content = long_content .. "\n"
    end

    args.on_read(nil, {
      role = "assistant",
      content = long_content
    })

    local last_line = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(chat.chat.winid))
    local win_height = vim.api.nvim_win_get_height(chat.chat.winid)
    local expected_scroll = last_line - win_height + 1
    local actual_scroll = vim.fn.line('w0', chat.chat.winid)

    assert.equal(expected_scroll, actual_scroll)

    -- Now press tab to get into the window
    keys = vim.api.nvim_replace_termcodes('<Tab>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    -- Another big response
    args.on_read(nil, {
      role = "assistant",
      content = long_content
    })

    -- This time we should stay put
    last_line = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(chat.chat.winid))
    win_height = vim.api.nvim_win_get_height(chat.chat.winid)
    expected_scroll = actual_scroll -- unchanged since last check
    actual_scroll = vim.fn.line('w0', chat.chat.winid)

    assert.equal(expected_scroll, actual_scroll)

    -- Now we'll close the window to later reopen it
    keys = vim.api.nvim_replace_termcodes(':q<CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    -- reopen the closed window
    chat = chat_window.build_and_mount()

    -- more long responses come in from the llm
    args.on_read(nil, {
      role = "assistant",
      content = long_content
    })

    -- and now ensure the autoscrolling continues to happen
    last_line = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(chat.chat.winid))
    win_height = vim.api.nvim_win_get_height(chat.chat.winid)
    expected_scroll = last_line - win_height + 1
    actual_scroll = vim.fn.line('w0', chat.chat.winid)

    assert.equal(expected_scroll, actual_scroll)
  end)

  it("handles llm errors gracefully", function()
    chat_window.build_and_mount()

    local llm_stub = stub(llm, "chat")

    local keys = vim.api.nvim_replace_termcodes('iwahoo<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    ---@type MakeChatRequestArgs
    local args = llm_stub.calls[1].refs[1]

    local log_stub = stub(util, "log")

    args.on_read("llm-error", nil)

    -- Populate a log file with mostly json decode errors I'm sure
    assert.stub(log_stub).was_called(1)

    -- This would mean the provider called on_read with no error and no response
    -- Happens sometimes with openai, probably my fault. Just testing to make
    -- sure it doesn't error.
    args.on_read(nil, nil)
  end)

  -- Having a lot of trouble testing this.
  pending("updates and resizes the nui window when the vim window resized TODO", function()
    local chat = chat_window.build_and_mount()

    local nui_height = vim.api.nvim_win_get_height(chat.chat.winid)
    local nui_width = vim.api.nvim_win_get_width(chat.chat.winid)

    local og_nui_height = nui_height
    local og_nui_width = nui_width

    -- Resize the Vim window
    vim.api.nvim_win_set_width(0, 200)
    vim.api.nvim_win_set_height(0, 300)

    vim.wait(20)

    nui_height = vim.api.nvim_win_get_height(chat.chat.winid)
    nui_width = vim.api.nvim_win_get_width(chat.chat.winid)

    assert.not_equals(og_nui_height, nui_height)
    assert.not_equals(og_nui_width, nui_width)
  end)
end)
