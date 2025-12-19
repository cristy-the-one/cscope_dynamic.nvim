---@mod cscope_dynamic.picker Result pickers
---@brief [[
--- Display cscope results using fzf-lua, telescope, or quickfix
---@brief ]]

local M = {}

--- Format result for display
---@param result table
---@return string
local function format_result(result)
  local parts = {
    result.display_path or result.filename,
    tostring(result.lnum),
  }

  if result.func and result.func ~= "" and result.func ~= "<global>" then
    table.insert(parts, result.func)
  end

  if result.text and result.text ~= "" then
    table.insert(parts, result.text)
  end

  return table.concat(parts, ":")
end

-- Forward declarations for fallback
local show_quickfix

--- Show results using fzf-lua
---@param config table
---@param results table[]
---@param query_type string
---@param symbol string
local function show_fzf_lua(config, results, query_type, symbol)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("cscope_dynamic: fzf-lua not available, falling back to quickfix", vim.log.levels.WARN)
    return show_quickfix(config, results, query_type, symbol)
  end

  local entries = {}
  for _, result in ipairs(results) do
    table.insert(entries, string.format(
      "%s:%d:%s",
      result.filename,
      result.lnum,
      result.text or ""
    ))
  end

  local cscope = require("cscope_dynamic")
  local title = cscope.get_query_desc(query_type) .. ": " .. symbol

  local opts = vim.tbl_deep_extend("force", {
    prompt = title .. "> ",
    fzf_opts = {
      ["--delimiter"] = ":",
      ["--nth"] = "1,3..",
      ["--with-nth"] = "1,2,3..",
    },
    actions = {
      ["default"] = function(selected)
        if selected and #selected > 0 then
          local entry = selected[1]
          local file, line = entry:match("^([^:]+):(%d+)")
          if file and line then
            vim.cmd("edit " .. vim.fn.fnameescape(file))
            vim.api.nvim_win_set_cursor(0, { tonumber(line), 0 })
            vim.cmd("normal! zz")
          end
        end
      end,
      ["ctrl-v"] = function(selected)
        if selected and #selected > 0 then
          local entry = selected[1]
          local file, line = entry:match("^([^:]+):(%d+)")
          if file and line then
            vim.cmd("vsplit " .. vim.fn.fnameescape(file))
            vim.api.nvim_win_set_cursor(0, { tonumber(line), 0 })
            vim.cmd("normal! zz")
          end
        end
      end,
      ["ctrl-x"] = function(selected)
        if selected and #selected > 0 then
          local entry = selected[1]
          local file, line = entry:match("^([^:]+):(%d+)")
          if file and line then
            vim.cmd("split " .. vim.fn.fnameescape(file))
            vim.api.nvim_win_set_cursor(0, { tonumber(line), 0 })
            vim.cmd("normal! zz")
          end
        end
      end,
      ["ctrl-t"] = function(selected)
        if selected and #selected > 0 then
          local entry = selected[1]
          local file, line = entry:match("^([^:]+):(%d+)")
          if file and line then
            vim.cmd("tabedit " .. vim.fn.fnameescape(file))
            vim.api.nvim_win_set_cursor(0, { tonumber(line), 0 })
            vim.cmd("normal! zz")
          end
        end
      end,
    },
    previewer = "builtin",
  }, config.picker_opts.fzf_lua or {})

  opts.winopts = vim.tbl_deep_extend("force", {
    height = 0.6,
    width = 0.8,
    preview = {
      layout = "vertical",
      vertical = "down:50%",
    },
    title = " " .. title .. " ",
    title_pos = "center",
  }, (config.picker_opts.fzf_lua or {}).winopts or {})

  fzf.fzf_exec(entries, opts)
end

--- Show results using telescope
---@param config table
---@param results table[]
---@param query_type string
---@param symbol string
local function show_telescope(config, results, query_type, symbol)
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    vim.notify("cscope_dynamic: telescope not available, falling back to quickfix", vim.log.levels.WARN)
    return show_quickfix(config, results, query_type, symbol)
  end

  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  local cscope = require("cscope_dynamic")
  local title = cscope.get_query_desc(query_type) .. ": " .. symbol

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 40 },
      { width = 6 },
      { remaining = true },
    },
  })

  local make_display = function(entry)
    return displayer({
      entry.display_path,
      tostring(entry.lnum),
      entry.text,
    })
  end

  local opts = vim.tbl_deep_extend("force", {}, config.picker_opts.telescope or {})

  pickers.new(opts, {
    prompt_title = title,
    finder = finders.new_table({
      results = results,
      entry_maker = function(entry)
        return {
          value = entry,
          display = make_display,
          ordinal = entry.display_path .. " " .. entry.text,
          filename = entry.filename,
          lnum = entry.lnum,
          display_path = entry.display_path,
          text = entry.text,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = conf.grep_previewer(opts),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          vim.cmd("edit " .. vim.fn.fnameescape(selection.filename))
          vim.api.nvim_win_set_cursor(0, { selection.lnum, 0 })
          vim.cmd("normal! zz")
        end
      end)
      return true
    end,
  }):find()
end

--- Show results in quickfix
---@param config table
---@param results table[]
---@param query_type string
---@param symbol string
show_quickfix = function(config, results, query_type, symbol)
  local cscope = require("cscope_dynamic")
  local title = cscope.get_query_desc(query_type) .. ": " .. symbol

  local qf_items = {}
  for _, result in ipairs(results) do
    table.insert(qf_items, {
      filename = result.filename,
      lnum = result.lnum,
      col = 1,
      text = result.text,
    })
  end

  vim.fn.setqflist({}, " ", {
    title = title,
    items = qf_items,
  })

  local qf_opts = config.picker_opts.quickfix or {}

  if qf_opts.open ~= false then
    local cmd = "copen"
    if qf_opts.position then
      cmd = qf_opts.position .. " " .. cmd
    end
    if qf_opts.height then
      cmd = cmd .. " " .. qf_opts.height
    end
    vim.cmd(cmd)
  end
end

--- Show results in location list
---@param config table
---@param results table[]
---@param query_type string
---@param symbol string
local function show_loclist(config, results, query_type, symbol)
  local cscope = require("cscope_dynamic")
  local title = cscope.get_query_desc(query_type) .. ": " .. symbol

  local loc_items = {}
  for _, result in ipairs(results) do
    table.insert(loc_items, {
      filename = result.filename,
      lnum = result.lnum,
      col = 1,
      text = result.text,
    })
  end

  vim.fn.setloclist(0, {}, " ", {
    title = title,
    items = loc_items,
  })

  local qf_opts = config.picker_opts.quickfix or {}

  if qf_opts.open ~= false then
    local cmd = "lopen"
    if qf_opts.height then
      cmd = cmd .. " " .. qf_opts.height
    end
    vim.cmd(cmd)
  end
end

--- Show results using configured picker
---@param config table
---@param results table[]
---@param query_type string
---@param symbol string
function M.show(config, results, query_type, symbol)
  if #results == 0 then
    vim.notify("cscope_dynamic: No results", vim.log.levels.INFO)
    return
  end

  -- Jump directly if single result and configured
  if #results == 1 and config.skip_picker_for_single_result then
    local result = results[1]
    vim.cmd("edit " .. vim.fn.fnameescape(result.filename))
    vim.api.nvim_win_set_cursor(0, { result.lnum, 0 })
    vim.cmd("normal! zz")
    return
  end

  local picker_name = config.picker or "fzf-lua"

  if picker_name == "fzf-lua" then
    show_fzf_lua(config, results, query_type, symbol)
  elseif picker_name == "telescope" then
    show_telescope(config, results, query_type, symbol)
  elseif picker_name == "loclist" or picker_name == "location" then
    show_loclist(config, results, query_type, symbol)
  else
    show_quickfix(config, results, query_type, symbol)
  end
end

return M
