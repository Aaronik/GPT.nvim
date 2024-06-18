local util        = require('gptmodels.util')
local com         = require('gptmodels.windows.common')
local Layout      = require("nui.layout")
local Popup       = require("nui.popup")
local llm         = require('gptmodels.llm')
local Store       = require('gptmodels.store')
local ollama      = require('gptmodels.providers.ollama')

local M           = {}

-- The system prompt for the LLM
---@param filetype string
---@param input_text string
---@param code_text string
---@return string, string[]
local code_prompt = function(filetype, input_text, code_text)
  local prompt_string = [[
    %s\n\n
    The extension of the language is %s.
    Here is the code:
    %s
  ]]

  local prompt = string.format(prompt_string, input_text, filetype, code_text)

  local system_string = [[
    You are a code generator.
    You only respond with code.
    Do not include any explanations.
    Do not use backticks. Do not include ``` at all."
  ]]

  local system = { string.format(system_string, input_text, code_text) }

  for _, filename in ipairs(Store.code:get_files()) do
    local file = io.open(filename, "r")
    if not file then break end
    local content = file:read("*all")
    file:close()

    table.insert(system, filename .. ":\n" .. content .. "\n\n")
  end

  return prompt, system
end

---@param input NuiPopup
local function set_input_top_border_text(input)
  local files = Store.code:get_files()
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
    "C-x xfer to deck",
  }

  local commands_str = " " .. table.concat(commands, " | ") .. " "
  input.border:set_text("bottom", commands_str, "center")
end

local function safe_render_right_text_from_store()
  -- if the window is closed and reopened again while a response is streaming in,
  -- right_bufnr will be wrong, and it won't get repopulated.
  -- So we're assigning to ..right.bufnr every time the window opens.
  local right_text = Store.code.right:read()
  local bufnr = Store.code.right.popup.bufnr
  if right_text and bufnr then
    com.safe_render_buffer_from_text(Store.code.right.popup.bufnr, right_text)
  end
end

-- Render the whole code window from the Store, respecting closed windows/buffers
local function safe_render_from_store()
  local left_text = Store.code.left:read()
  local left_buf = Store.code.left.popup.bufnr or -1
  if left_text then com.safe_render_buffer_from_text(left_buf, left_text) end

  local right_text = Store.code.right:read()
  local right_buf = Store.code.right.popup.bufnr or -1
  if right_text then com.safe_render_buffer_from_text(right_buf, right_text) end

  local input_text = Store.code.input:read()
  local input_buf = Store.code.input.popup.bufnr or -1
  if input_text then com.safe_render_buffer_from_text(input_buf, input_text) end

  -- Get the files back
  set_input_top_border_text(Store.code.input.popup)
end

local on_CR = function(input_bufnr, left_bufnr, right_bufnr)
  local input_lines = vim.api.nvim_buf_get_lines(input_bufnr, 0, -1, false)
  local input_text = table.concat(input_lines, "\n")
  local left_lines = vim.api.nvim_buf_get_lines(left_bufnr, 0, -1, false)
  local left_text = table.concat(left_lines, "\n")

  local filetype = vim.bo[left_bufnr].filetype

  local prompt, system = code_prompt(filetype, input_text, left_text)

  -- Clear the right window so the next response doesn't append to the previous one
  Store.code.right:clear()

  -- Loading indicator
  com.safe_render_buffer_from_text(right_bufnr, "Loading...")

  -- Nuke existing jobs
  if Store:get_job() then
    Store:get_job().die()
  end

  local job = llm.generate({
    llm = {
      stream = true,
      prompt = prompt,
      system = system,
    },
    on_read = function(err, response)
      if err then
        Store.code.right:append(err)
        safe_render_right_text_from_store()
        return
      end

      -- No response _and_ no error? Weird. Happens though.
      if not response then return end

      Store.code.right:append(response)

      safe_render_right_text_from_store()

      -- scroll to the bottom if the window's still open and the user is not in it
      -- (If they're in it, the priority is for them to be able to nav around and yank)
      local right_winid = Store.code.right.popup.winid or 1
      if vim.api.nvim_win_is_valid(right_winid) and vim.api.nvim_get_current_win() ~= right_winid then
        vim.api.nvim_win_set_cursor(
          right_winid, { vim.api.nvim_buf_line_count(Store.code.right.popup.bufnr), 0 }
        )
      end
    end,
    on_end = function()
      Store:clear_job()
    end
  })

  Store:register_job(job)
end

---@param right_popup NuiPopup
local function render_model_name(right_popup)
  right_popup.border:set_text("top", " " .. com.model_display_name() .. " ", "center")
end

---@param selected_lines string[] | nil
---@return { input: NuiPopup, right: NuiPopup, left: NuiPopup }
function M.build_and_mount(selected_lines)
  ---@type NuiPopup
  local left = Popup(com.build_common_popup_opts("On Deck"))
  ---@type NuiPopup
  local right = Popup(com.build_common_popup_opts(com.model_display_name()))
  ---@type NuiPopup
  local input = Popup(com.build_common_popup_opts("Prompt"))

  set_input_bottom_border_text(input)

  -- Register popups with store
  Store.code.right.popup = right
  Store.code.left.popup = left
  Store.code.input.popup = input

  -- Fetch ollama models so user can work with what they have on their system
  ollama.fetch_models(function(err, models)
    -- TODO Change this too
    if err then return util.log(err) end
    if not models or #models == 0 then return end
    Store.llm_models.ollama = models
    local is_ollama = util.contains_line(models, Store.llm_model)
    local is_openai = util.contains_line(Store.llm_models.openai, Store.llm_model)
    if not is_ollama and not is_openai then
      Store:set_llm("ollama", models[1])
      render_model_name(right)
    end
  end)

  -- Show models only if openai key
  has_openai_key = util.ensure_env_var("OPENAI_API_KEY")
  if not has_openai_key then
    Store.llm_models.openai = {}
  end

  -- Turn off syntax highlighting for input buffer.
  vim.bo[input.bufnr].filetype = "txt"
  vim.bo[input.bufnr].syntax = ""

  -- Make input a 'scratch' buffer, effectively making it a temporary buffer
  vim.bo[input.bufnr].buftype = "nofile"

  -- Set buffers to same filetype as current file, for highlighting
  vim.bo[left.bufnr].filetype = vim.bo.filetype
  vim.bo[right.bufnr].filetype = vim.bo.filetype

  -- When the user opened this from visual mode with text
  if selected_lines then
    vim.api.nvim_buf_set_lines(left.bufnr, 0, -1, true, selected_lines)

    -- On open, save the text to the store, so next open contains that text
    Store.code.left:clear()
    Store.code.left:append(table.concat(selected_lines, "\n"))

    -- If selected lines are given, it's like a new session, so we'll nuke all else
    local extent_job = Store:get_job()
    if extent_job then
      extent_job.die()
      vim.wait(100, function() return extent_job.done() end)
    end
    Store.code.input:clear()
    Store.code.right:clear()

    Store.code:clear_files()
  else
    -- When the store already has some data
    -- If a selection is passed in, though, then it gets a new session
    safe_render_from_store()
  end

  local missing_deps_error_message = com.check_deps()
  if missing_deps_error_message then
    com.safe_render_buffer_from_text(right.bufnr, missing_deps_error_message)
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
        Layout.Box(left, { size = "50%" }),
        Layout.Box(right, { size = "50%" }),
      }, { dir = "row", size = "80%" }),
      Layout.Box(input, { size = "20%" }),
    }, { dir = "col" })
  )

  -- For input, set <CR>
  vim.api.nvim_buf_set_keymap(input.bufnr, "n", "<CR>", "",
    {
      noremap = true,
      silent = true,
      callback = function()
        on_CR(input.bufnr, left.bufnr, right.bufnr)
      end
    }
  )

  -- For input, save to populate on next open
  input:on("InsertLeave",
    function()
      local input_lines = vim.api.nvim_buf_get_lines(input.bufnr, 0, -1, true)
      Store.code.input:clear()
      Store.code.input:append(table.concat(input_lines, "\n"))
    end
  )

  -- recalculate nui window when vim window resizes
  input:on("VimResized", function()
    layout:update()
  end)

  -- Further Keymaps
  local bufs = { left.bufnr, right.bufnr, input.bufnr }
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

    -- Ctl-n to reset session
    vim.api.nvim_buf_set_keymap(buf, "", "<C-n>", "", {
      noremap = true,
      silent = true,
      callback = function()
        Store.code:clear()
        for _, bu in ipairs(bufs) do
          vim.api.nvim_buf_set_lines(bu, 0, -1, true, {})
        end
        set_input_top_border_text(input)
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
              render_model_name(right)
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

    -- Ctrl-j to cycle forward through llms
    vim.api.nvim_buf_set_keymap(buf, "", "<C-j>", "", {
      noremap = true,
      silent = true,
      callback = function()
        Store:cycle_model_forward()
        render_model_name(right)
      end
    })

    -- Ctrl-k to cycle forward through llms
    vim.api.nvim_buf_set_keymap(buf, "", "<C-k>", "", {
      noremap = true,
      silent = true,
      callback = function()
        Store:cycle_model_backward()
        render_model_name(right)
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
              Store.code:append_file(selection[1])
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
        Store.code:clear_files()
        set_input_top_border_text(input)
      end
    })

    -- Ctl-x to clear files
    vim.api.nvim_buf_set_keymap(buf, "", "<C-x>", "", {
      noremap = true,
      silent = true,
      callback = function()
        local right_text = Store.code.right:read()
        if not right_text then return end
        Store.code.left:clear()
        Store.code.left:append(right_text)
        Store.code.right:clear()
        com.safe_render_buffer_from_text(right.bufnr, Store.code.right:read() or "")
        com.safe_render_buffer_from_text(left.bufnr, Store.code.left:read() or "")
      end
    })

    -- q to exit
    vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
      noremap = true,
      silent = true,
      callback = function()
        layout:unmount()
      end,
    })
  end

  -- Once this mounts, our popups now have a winid for as long as the layout is mounted
  layout:mount()

  -- Wrap lines, because these are small windows and it's nicer
  vim.wo[left.winid].wrap = true
  vim.wo[right.winid].wrap = true
  vim.wo[input.winid].wrap = true

  return {
    input = input,
    right = right,
    left = left
  }
end

return M
