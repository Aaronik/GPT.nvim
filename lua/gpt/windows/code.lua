local util   = require('gpt.util')
local com    = require('gpt.windows.common')
local Layout = require("nui.layout")
local Popup  = require("nui.popup")
local llm    = require('gpt.llm')
local Store  = require('gpt.store')

local M      = {}

---@param bufnr integer
---@param text string
local function render_buffer_from_text(bufnr, text)
  local response_lines = vim.split(text or "", "\n")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, response_lines)
end

---@param filetype string
---@param input_text string
---@param code_text string
---@return string, string
local code_prompt = function (filetype, input_text, code_text)

  local prompt_string = ""
  prompt_string = prompt_string .. "%s\n\n"
  prompt_string = prompt_string .. "The extension of the language is %s.\n"
  prompt_string = prompt_string .. "Here is the code:\n\n"
  prompt_string = prompt_string .. "%s"

  local prompt = string.format(prompt_string, input_text, filetype, code_text)

  local system_string = ""
  system_string = system_string .. "You are a code generator.\n"
  system_string = system_string .. "You only respond with code.\n"
  system_string = system_string .. "Do not explain the code.\n"
  system_string = system_string .. "Do not use backticks. Do not include ``` at all.\n"

  local system = string.format(system_string, input_text, code_text)

  return prompt, system
end

local on_CR = function(input_bufnr, code_bufnr, right_bufnr)
  local input_lines = vim.api.nvim_buf_get_lines(input_bufnr, 0, -1, false)
  local input_text = table.concat(input_lines, "\n")
  local code_lines = vim.api.nvim_buf_get_lines(code_bufnr, 0, -1, false)
  local code_text = table.concat(code_lines, "\n")

  local filetype = vim.api.nvim_buf_get_option(code_bufnr, 'filetype')

  local prompt, system = code_prompt(filetype, input_text, code_text)

  -- Clear input
  vim.api.nvim_buf_set_lines(input_bufnr, 0, -1, true, {})

  -- Loading indicator
  render_buffer_from_text(right_bufnr, "Loading...")

  local job = llm.generate({
    llm = {
      model = "llama3",
      stream = true,
      prompt = prompt,
      system = system,
    },
    on_read = function(_, response)
      Store.code.right.append(response)
      render_buffer_from_text(right_bufnr, Store.code.right.read())
    end,
    on_end = function ()
      Store.code.right.clear()
      Store.clear_job()
    end
  })

  Store.register_job(job)
end

local function on_q(layout)
  local job = Store.get_job()
  if job ~= nil then
    job.die()
    Store.clear_job()
  end
  layout:unmount()
end

---@param selected_text string[] | nil
function M.build_and_mount(selected_text)
  local left_popup = Popup(com.build_common_popup_opts("Current"))
  local right_popup = Popup(com.build_common_popup_opts("Code"))
  local input_popup = Popup(com.build_common_popup_opts("Prompt"))

  -- Turn off syntax highlighting for input buffer.
  vim.api.nvim_buf_set_option(input_popup.bufnr, 'filetype', 'txt')
  vim.api.nvim_buf_set_option(input_popup.bufnr, 'syntax', '')

  -- Make input a 'scratch' buffer, effectively making it a temporary buffer
  vim.api.nvim_buf_set_option(input_popup.bufnr, "buftype", "nofile")

  -- Set buffers to same filetype as current file, for highlighting
  vim.api.nvim_buf_set_option(left_popup.bufnr, 'filetype', vim.bo.filetype)
  vim.api.nvim_buf_set_option(right_popup.bufnr, 'filetype', vim.bo.filetype)

  -- When the user opened this from visual mode with text
  if selected_text then
    vim.api.nvim_buf_set_lines(left_popup.bufnr, 0, -1, true, selected_text)
  end

  -- When the store already has some data
  -- If a selection is passed in, though, then it gets a new session
  if not selected_text then
    local left_content = Store.code.left.read()
    if left_content then render_buffer_from_text(left_popup.bufnr, left_content) end

    local right_content = Store.code.right.read()
    if right_content then render_buffer_from_text(right_popup.bufnr, right_content) end

    local input_content = Store.code.input.read()
    if input_content then render_buffer_from_text(input_popup.bufnr, input_content) end
  end

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
      Layout.Box({
        Layout.Box(left_popup, { size = "50%" }),
        Layout.Box(right_popup, { size = "50%" }),
      }, { dir = "row", size = "80%" }),
      Layout.Box(input_popup, { size = "22%" }),
    }, { dir = "col" })
  )

  -- Set <CR> on input
  vim.api.nvim_buf_set_keymap(input_popup.bufnr, "n", "<CR>", "",
    { noremap = true, silent = true, callback = function() on_CR(input_popup.bufnr, left_popup.bufnr, right_popup.bufnr) end }
  )

  -- Further Keymaps
  local bufs = { left_popup.bufnr, right_popup.bufnr, input_popup.bufnr }
  for i, buf in ipairs(bufs) do
    -- Tab cycles through windows
    vim.api.nvim_buf_set_keymap(buf, "n", "<Tab>", "", {
      noremap = true,
      silent = true,
      callback = function()
        local next_buf_index = (i % #bufs) + 1
        local next_win = vim.fn.bufwinid(bufs[next_buf_index])
        vim.api.nvim_set_current_win(next_win)
      end
    })

    -- Shift-Tab cycles through windows in reverse
    vim.api.nvim_buf_set_keymap(buf, "n", "<S-Tab>", "", {
      noremap = true,
      silent = true,
      callback = function()
        local prev_buf_index = (i - 2) % #bufs + 1
        local prev_win = vim.fn.bufwinid(bufs[prev_buf_index])
        vim.api.nvim_set_current_win(prev_win)
      end
    })

    -- q to exit -- TODO This is probably more personal config. Consider
    -- removing this before it goes live. Or making it optional or something
    -- else.
    vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
      noremap = true,
      silent = true,
      callback = function() on_q(layout) end,
    })
  end

  layout:mount()

  -- start window in insert mode
  vim.api.nvim_command('startinsert')

  return {
    input_bufnr = input_popup.bufnr,
    left_bufnr = left_popup.bufnr,
    right_bufnr = right_popup.bufnr
  }
end

return M