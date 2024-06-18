local util = require('gptmodels.util')
local com = require('gptmodels.windows.common')
local Layout = require("nui.layout")
local Popup = require("nui.popup")
local llm = require("gptmodels.llm")
local Store = require("gptmodels.store")
local ollama = require("gptmodels.providers.ollama")

local M = {}

---@param bufnr integer
---@param messages LlmMessage[]
local safe_render_buffer_from_messages = function(bufnr, messages)
  if not bufnr then return end -- can happen when popup has been unmounted
  local buf_loaded = vim.api.nvim_buf_is_loaded(bufnr)
  local buf_valid = vim.api.nvim_buf_is_valid(bufnr)
  if not (buf_loaded and buf_valid) then return end

  local lines = {}
  for _, message in ipairs(messages) do
    local message_content = vim.split(message.content, "\n")
    lines = util.merge_tables(lines, message_content)
    table.insert(lines, "---")
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
end

---@param input_bufnr integer
---@param chat_bufnr integer
local on_CR = function(input_bufnr, chat_bufnr)
  local input_lines = vim.api.nvim_buf_get_lines(input_bufnr, 0, -1, false)
  local input_text = table.concat(input_lines, "\n")

  -- Clear input buf
  vim.api.nvim_buf_set_lines(input_bufnr, 0, -1, true, {})

  Store.chat.chat:append({ role = "user", content = input_text })
  safe_render_buffer_from_messages(chat_bufnr, Store.chat.chat:read())

  local file_messages = {}
  for _, filename in ipairs(Store.chat:get_files()) do
    local file = io.open(filename, "r")
    if not file then break end
    local content = file:read("*all")
    file:close()

    table.insert(file_messages, {
      role = "system",
      content = filename .. ":\n\n" .. content
    })
  end
  local messages = util.merge_tables(Store.chat.chat:read(), file_messages)

  local jorb = llm.chat({
    llm = {
      stream = true,
      messages = messages,
    },
    on_read = function(err, message)
      if err then
        -- P("code found err: " .. err)
        Store.chat.chat:append({ role = "assistant", content = err })
        safe_render_buffer_from_messages(Store.chat.chat.popup.bufnr, Store.chat.chat:read())
        return
      end


      -- No response _and_ no error? Weird. Happens though.
      if message then
        Store.chat.chat:append(message)
      end

      safe_render_buffer_from_messages(Store.chat.chat.popup.bufnr, Store.chat.chat:read())

      -- scroll to the bottom if the window's still open and the user is not in it
      -- (If they're in it, the priority is for them to be able to nav around and yank)
      local chat_winid = Store.chat.chat.popup.winid or 1 -- nonsense winid, it shouldn't ever be nil
      if vim.api.nvim_win_is_valid(chat_winid) and vim.api.nvim_get_current_win() ~= chat_winid then
        vim.api.nvim_win_set_cursor(chat_winid,
          { vim.api.nvim_buf_line_count(Store.chat.chat.popup.bufnr), 0 }
        )
      end
    end,
    on_end = function()
      Store:clear_job()
    end
  })

  Store:register_job(jorb)
end

local function on_tab(i, bufs)
  local next_buf_index = (i % #bufs) + 1
  local next_win = vim.fn.bufwinid(bufs[next_buf_index])
  vim.api.nvim_set_current_win(next_win)
end

local function on_s_tab(i, bufs)
  local next_buf_index = (i % #bufs) + 1
  local next_win = vim.fn.bufwinid(bufs[next_buf_index])
  vim.api.nvim_set_current_win(next_win)
end

---@param input NuiPopup
local function set_input_top_border_text(input)
  local files = Store.chat:get_files()
  if #files == 0 then
    input.border:set_text(
      "top",
      " Prompt ",
      "center"
    )
  else
    local files_string = table.concat(files, ", ")
    input.border:set_text(
      "top",
      " Prompt + " .. files_string .. " ",
      "center"
    )
  end
end


-- available controls are found at the bottom of the input popup
---@param input NuiPopup
local function set_input_bottom_border_text(input)
  local commands = {
    "q quit",
    "[S]Tab cycle windows",
    "C-c cancel request",
    "C-j/k/p cycle/pick models",
    "C-n clear all",
    "C-f/g add/clear files",
  }

  local commands_str = " " .. table.concat(commands, " | ") .. " "
  input.border:set_text("bottom", commands_str, "center")
end

local function chat_title()
  return "Chat w/ " .. Store.llm_provider .. "." .. Store.llm_model
end

---@param chat NuiPopup
local function set_chat_title(chat)
  chat.border:set_text("top", " " .. chat_title() .. " ", "center")
end

---@param selected_text string[] | nil
---@return { input: NuiPopup, chat: NuiPopup }
function M.build_and_mount(selected_text)
  ---@type NuiPopup
  local chat = Popup(com.build_common_popup_opts(chat_title()))
  ---@type NuiPopup
  local input = Popup(com.build_common_popup_opts("Prompt")) -- the Prompt part will be overwritten by calls to set_input_text

  -- available controls are found at the bottom of the input popup
  set_input_bottom_border_text(input)

  -- Register popups with store
  Store.chat.chat.popup = chat
  Store.chat.input.popup = input

  -- Fetch ollama models so user can work with what they have on their system
  ollama.fetch_models(function(err, models)
    -- TODO If there's an issue fetching, I want to display that to the user.
    if err then return util.log(err) end
    if not models or #models == 0 then return end
    Store.llm_models.ollama = models
    local is_ollama = util.contains_line(models, Store.llm_model)
    local is_openai = util.contains_line(Store.llm_models.openai, Store.llm_model)
    if not is_ollama and not is_openai then
      Store:set_llm("ollama", models[1])
      set_chat_title(chat)
    end
  end)

  -- Show models only if openai key
  has_openai_key = util.ensure_env_var("OPENAI_API_KEY")
  if not has_openai_key then
    Store.llm_models.openai = {}
  end

  -- Input window is text with no syntax
  vim.bo[input.bufnr].filetype = 'txt'
  vim.bo[input.bufnr].syntax = ''

  -- Make input a 'scratch' buffer, effectively making it a temporary buffer
  vim.bo[input.bufnr].buftype = "nofile"

  -- Chat in markdown
  vim.bo[chat.bufnr].filetype = 'markdown'

  vim.api.nvim_buf_set_keymap(
    input.bufnr,
    "n",
    "<CR>",
    "",
    { noremap = true, silent = true, callback = function() on_CR(input.bufnr, chat.bufnr) end }
  )

  local layout = Layout(
    {
      position = "50%",
      relative = "editor",
      size = {
        width = "90%",
        height = "90%",
      },
    },
    Layout.Box({
      Layout.Box(chat, { size = "80%" }),
      Layout.Box(input, { size = "22%" }),
    }, { dir = "col" })
  )

  -- recalculate nui window when vim window resizes
  input:on("VimResized", function()
    layout:update()
  end)

  -- For input, save to populate on next open
  input:on("InsertLeave",
    function()
      local input_lines = vim.api.nvim_buf_get_lines(input.bufnr, 0, -1, true)
      Store.chat.input:clear()
      Store.chat.input:append(table.concat(input_lines, "\n"))
    end
  )

  -- Once this mounts, our popups now have a winid for as long as the layout is mounted
  layout:mount()

  -- Wrap lines for modern Neovim API
  vim.wo[chat.winid].wrap = true
  vim.wo[input.winid].wrap = true

  -- Add text selection to input buf
  if selected_text then
    -- If selected lines are given, it's like a new session, so we'll nuke all else
    local extent_job = Store:get_job()
    if extent_job then
      extent_job.die()
      vim.wait(100, function() return extent_job.done() end)
    end

    -- clear chat window
    vim.api.nvim_buf_set_lines(chat.bufnr, 0, -1, true, {})
    Store.chat.chat:clear()

    -- clear files
    Store.chat:clear_files()

    -- clear / add selection to input
    Store.chat.input:clear()
    vim.api.nvim_buf_set_lines(input.bufnr, 0, -1, true, selected_text)

    -- Go to bottom of input and enter insert mode
    local keys = vim.api.nvim_replace_termcodes('<Esc>Go', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)
  else
    -- If there's saved input, render that
    local input_content = Store.chat.input:read()
    if input_content then com.safe_render_buffer_from_text(input.bufnr, input_content) end

    -- If there's a chat history, open with that.
    safe_render_buffer_from_messages(chat.bufnr, Store.chat.chat:read())

    -- Get the files back
    set_input_top_border_text(input)
  end

  local missing_deps_error_message = com.check_deps()
  if missing_deps_error_message then
    com.safe_render_buffer_from_text(chat.bufnr, missing_deps_error_message)
  end

  -- keymaps
  local bufs = { chat.bufnr, input.bufnr }
  for i, buf in ipairs(bufs) do
    -- Tab cycles through windows
    vim.api.nvim_buf_set_keymap(buf, "n", "<Tab>", "", {
      noremap = true,
      silent = true,
      callback = function() on_tab(i, bufs) end,
    })

    -- Shift-Tab cycles through windows in reverse
    vim.api.nvim_buf_set_keymap(buf, "n", "<S-Tab>", "", {
      noremap = true,
      silent = true,
      callback = function() on_s_tab(i, bufs) end,
    })

    -- Ctl-n to reset session
    vim.api.nvim_buf_set_keymap(buf, "", "<C-n>", "", {
      noremap = true,
      silent = true,
      callback = function()
        Store.chat:clear()
        for _, bu in ipairs(bufs) do
          vim.api.nvim_buf_set_lines(bu, 0, -1, true, {})
        end
        set_input_top_border_text(input)
      end
    })

    -- Ctl-f to include files
    vim.api.nvim_buf_set_keymap(buf, "", "<C-f>", "", {
      noremap = true,
      silent = true,
      callback = function()
        local theme = require('telescope.themes').get_dropdown({ winblend = 10 })
        require('telescope.builtin').find_files(util.merge_tables(theme, {
          attach_mappings = function(_, map)
            map('i', '<CR>', function(prompt_bufnr)
              local selection = require('telescope.actions.state').get_selected_entry()
              Store.chat:append_file(selection[1])
              set_input_top_border_text(input)
              require('telescope.actions').close(prompt_bufnr)
            end)
            return true
          end
        }))
      end
    })

    -- Ctl-g to clear files
    vim.api.nvim_buf_set_keymap(buf, "", "<C-g>", "", {
      noremap = true,
      silent = true,
      callback = function()
        Store.chat:clear_files()
        set_input_top_border_text(input)
      end
    })

    -- Ctrl-p to open model picker
    vim.api.nvim_buf_set_keymap(buf, "", "<C-p>", "", {
      noremap = true,
      silent = true,
      callback = function()
        local theme = require('telescope.themes').get_dropdown({ winblend = 10 })
        local conf = require('telescope.config').values
        local actions = require('telescope.actions')
        local state = require('telescope.actions.state')
        local pickers = require('telescope.pickers')

        local opts = util.merge_tables(theme, {
          attach_mappings = function(_, map)
            map('i', '<CR>', function(bufnr)
              local selection = state.get_selected_entry()
              local model_string = selection[1]
              local provider = vim.split(model_string, ".", { plain = true })[1]
              local model = vim.split(model_string, ".", { plain = true })[2]
              if not (provider and model) then return end
              Store:set_llm(provider, model)
              set_chat_title(chat)
              actions.close(bufnr)
            end)
            return true
          end
        })

        pickers.new(opts, {
          prompt_title = "models",
          finder = require('telescope.finders').new_table {
            results = Store:llm_model_strings()
          },
          sorter = conf.generic_sorter({}),
        }):find()
      end
    })

    -- Ctrl-c to kill active job
    vim.api.nvim_buf_set_keymap(buf, "", "<C-c>", "", {
      noremap = true,
      silent = true,
      callback = function()
        if Store:get_job() then
          Store:get_job().die()
        end
      end
    })

    -- Ctrl-j to cycle forward through llms
    vim.api.nvim_buf_set_keymap(buf, "", "<C-j>", "", {
      noremap = true,
      silent = true,
      callback = function()
        Store:cycle_model_forward()
        set_chat_title(chat)
      end
    })

    -- Ctrl-k to cycle forward through llms
    vim.api.nvim_buf_set_keymap(buf, "", "<C-k>", "", {
      noremap = true,
      silent = true,
      callback = function()
        Store:cycle_model_backward()
        set_chat_title(chat)
      end
    })

    -- "q" exits from the thing
    vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
      noremap = true,
      silent = true,
      callback = function() layout:unmount() end,
    })
  end

  return {
    input = input,
    chat = chat
  }
end

return M
