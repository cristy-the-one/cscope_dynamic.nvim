---@mod cscope_dynamic.commands User commands
---@brief [[
--- Provides :Cscope, :CscopeInit, and related commands
--- Compatible with traditional cscope command syntax
---@brief ]]

local M = {}

--- Setup user commands
function M.setup()
  local cscope = require("cscope_dynamic")

  -- Main :Cscope command (aliases: :Cs)
  -- Usage: :Cscope find <type> <symbol>
  --        :Cs f <type> <symbol>
  vim.api.nvim_create_user_command("Cscope", function(opts)
    M.handle_cscope_cmd(opts.fargs)
  end, {
    nargs = "*",
    complete = function(arg_lead, cmd_line, cursor_pos)
      return M.complete_cscope(arg_lead, cmd_line, cursor_pos)
    end,
    desc = "Cscope commands",
  })

  -- Short alias
  vim.api.nvim_create_user_command("Cs", function(opts)
    M.handle_cscope_cmd(opts.fargs)
  end, {
    nargs = "*",
    complete = function(arg_lead, cmd_line, cursor_pos)
      return M.complete_cscope(arg_lead, cmd_line, cursor_pos)
    end,
    desc = "Cscope commands (short)",
  })

  -- Initialize command
  vim.api.nvim_create_user_command("CscopeInit", function()
    cscope.init()
  end, {
    desc = "Initialize cscope database",
  })

  -- Rebuild command
  vim.api.nvim_create_user_command("CscopeRebuild", function()
    cscope.rebuild(function(success)
      if success then
        vim.notify("cscope_dynamic: Database rebuilt", vim.log.levels.INFO)
      end
    end)
  end, {
    desc = "Rebuild cscope database",
  })

  -- Debug command to test file finding
  vim.api.nvim_create_user_command("CscopeDebug", function()
    local utils = require("cscope_dynamic.utils")
    local root = cscope.state.project_root or vim.fn.getcwd()
    local cmd = utils.make_find_cmd(cscope.config, root)
    
    vim.notify("Project root: " .. root, vim.log.levels.INFO)
    vim.notify("Find command: " .. cmd, vim.log.levels.INFO)
    
    -- Run it and show results
    local success, files, stderr = utils.sync_cmd(cmd)
    if success then
      vim.notify("Found " .. #files .. " files", vim.log.levels.INFO)
      if #files > 0 and #files <= 10 then
        for _, f in ipairs(files) do
          vim.notify("  " .. f, vim.log.levels.INFO)
        end
      elseif #files > 10 then
        for i = 1, 5 do
          vim.notify("  " .. files[i], vim.log.levels.INFO)
        end
        vim.notify("  ... and " .. (#files - 5) .. " more", vim.log.levels.INFO)
      end
    else
      vim.notify("Command failed: " .. table.concat(stderr or {}, "\n"), vim.log.levels.ERROR)
    end
  end, {
    desc = "Debug cscope file finding",
  })

  -- Status command
  vim.api.nvim_create_user_command("CscopeStatus", function()
    local db = require("cscope_dynamic.db")
    local status = db.status(cscope.state)

    local lines = {
      "Cscope Dynamic Status:",
      "",
      "Initialized: " .. tostring(status.initialized),
      "Updating: " .. tostring(status.updating),
      "Project root: " .. (status.project_root or "N/A"),
      "",
      "Big DB exists: " .. tostring(status.big_db_exists),
      "Small DB exists: " .. tostring(status.small_db_exists),
      "Files in big DB: " .. status.big_files_count,
      "Files in small DB: " .. status.small_files_count,
    }

    if status.last_big_update > 0 then
      local ago = os.time() - status.last_big_update
      table.insert(lines, "Last big update: " .. ago .. "s ago")
    end

    -- Display in floating window
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)

    local width = 50
    local height = #lines + 2

    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      col = (vim.o.columns - width) / 2,
      row = (vim.o.lines - height) / 2,
      style = "minimal",
      border = "rounded",
      title = " Cscope Status ",
      title_pos = "center",
    })

    -- Close on any key
    vim.keymap.set("n", "q", function()
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf })

    vim.keymap.set("n", "<Esc>", function()
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf })
  end, {
    desc = "Show cscope status",
  })

  -- Prompt commands for each query type
  local query_types = {
    { cmd = "CsFind", short = "s", desc = "Find symbol" },
    { cmd = "CsFindDef", short = "g", desc = "Find definition" },
    { cmd = "CsFindCallers", short = "c", desc = "Find callers" },
    { cmd = "CsFindText", short = "t", desc = "Find text" },
    { cmd = "CsFindEgrep", short = "e", desc = "Find egrep pattern" },
    { cmd = "CsFindFile", short = "f", desc = "Find file" },
    { cmd = "CsFindInclude", short = "i", desc = "Find includers" },
    { cmd = "CsFindCalled", short = "d", desc = "Find called by" },
    { cmd = "CsFindAssign", short = "a", desc = "Find assignments" },
  }

  for _, qt in ipairs(query_types) do
    vim.api.nvim_create_user_command(qt.cmd, function(opts)
      local symbol = opts.args
      if not symbol or symbol == "" then
        symbol = vim.fn.expand("<cword>")
      end
      cscope.query(qt.short, symbol)
    end, {
      nargs = "?",
      desc = qt.desc,
    })
  end
end

--- Handle :Cscope command
---@param args string[]
function M.handle_cscope_cmd(args)
  local cscope = require("cscope_dynamic")

  if #args == 0 then
    -- Show help
    M.show_help()
    return
  end

  local subcmd = args[1]:lower()

  -- Handle find command
  if subcmd == "find" or subcmd == "f" then
    if #args < 2 then
      vim.notify("Usage: :Cscope find <type> [symbol]", vim.log.levels.WARN)
      return
    end

    local query_type = args[2]:lower()
    local symbol = args[3] or vim.fn.expand("<cword>")

    -- Map numeric and letter types
    local type_map = {
      ["0"] = "s", ["s"] = "s",
      ["1"] = "g", ["g"] = "g",
      ["2"] = "d", ["d"] = "d",
      ["3"] = "c", ["c"] = "c",
      ["4"] = "t", ["t"] = "t",
      ["6"] = "e", ["e"] = "e",
      ["7"] = "f", ["f"] = "f",
      ["8"] = "i", ["i"] = "i",
      ["9"] = "a", ["a"] = "a",
    }

    local mapped_type = type_map[query_type]
    if not mapped_type then
      vim.notify("Unknown query type: " .. query_type, vim.log.levels.ERROR)
      return
    end

    cscope.query(mapped_type, symbol)

  -- Handle database commands
  elseif subcmd == "db" then
    M.handle_db_cmd(vim.list_slice(args, 2))

  -- Handle add/show/kill (legacy compatibility)
  elseif subcmd == "add" then
    vim.notify("Use :CscopeInit to add databases", vim.log.levels.INFO)

  elseif subcmd == "show" then
    vim.cmd("CscopeStatus")

  elseif subcmd == "kill" then
    -- Clear state
    cscope.state.initialized = false
    cscope.state.small_files = {}
    vim.notify("Cscope state cleared", vim.log.levels.INFO)

  elseif subcmd == "reset" then
    cscope.load_databases()
    vim.notify("Cscope databases reloaded", vim.log.levels.INFO)

  elseif subcmd == "help" or subcmd == "?" then
    M.show_help()

  else
    -- Maybe it's a direct query type
    local type_map = {
      s = "s", g = "g", d = "d", c = "c",
      t = "t", e = "e", f = "f", i = "i", a = "a",
    }

    if type_map[subcmd] then
      local symbol = args[2] or vim.fn.expand("<cword>")
      cscope.query(type_map[subcmd], symbol)
    else
      vim.notify("Unknown command: " .. subcmd .. ". Use :Cscope help", vim.log.levels.ERROR)
    end
  end
end

--- Handle :Cscope db subcommand
---@param args string[]
function M.handle_db_cmd(args)
  local cscope = require("cscope_dynamic")

  if #args == 0 then
    vim.cmd("CscopeStatus")
    return
  end

  local subcmd = args[1]:lower()

  if subcmd == "build" or subcmd == "rebuild" then
    cscope.rebuild(function(success)
      if success then
        vim.notify("Database rebuilt", vim.log.levels.INFO)
      end
    end)

  elseif subcmd == "show" or subcmd == "status" then
    vim.cmd("CscopeStatus")

  elseif subcmd == "add" then
    -- For now, just init
    cscope.init()

  elseif subcmd == "rm" or subcmd == "remove" then
    -- Remove database files
    if cscope.state.big_db_path then
      vim.fn.delete(cscope.state.big_db_path)
      vim.fn.delete(cscope.state.small_db_path)
      vim.fn.delete(cscope.state.files_list_path)
    end
    cscope.state.initialized = false
    vim.notify("Database files removed", vim.log.levels.INFO)

  else
    vim.notify("Unknown db command: " .. subcmd, vim.log.levels.ERROR)
  end
end

--- Show help
function M.show_help()
  local help = [[
Cscope Dynamic Commands:

:Cscope find <type> [symbol]   - Find symbol (alias: :Cs f)
:Cscope db build               - Rebuild database
:Cscope db show                - Show database status
:Cscope reset                  - Reset cscope connections

:CscopeInit                    - Initialize database
:CscopeRebuild                 - Rebuild database
:CscopeStatus                  - Show status

Query types:
  s - Find this C symbol
  g - Find global definition
  c - Find callers of this function
  t - Find this text string
  e - Find this egrep pattern
  f - Find this file
  i - Find files #including this file
  d - Find functions called by this function
  a - Find places where this symbol is assigned

Examples:
  :Cs f g main                 - Find definition of 'main'
  :Cs f c printf               - Find callers of 'printf'
  :Cscope find s malloc        - Find symbol 'malloc'
]]

  vim.notify(help, vim.log.levels.INFO)
end

--- Command completion
---@param arg_lead string
---@param cmd_line string
---@param cursor_pos number
---@return string[]
function M.complete_cscope(arg_lead, cmd_line, cursor_pos)
  local parts = vim.split(cmd_line, "%s+")

  -- First argument
  if #parts <= 2 then
    local options = { "find", "f", "db", "show", "reset", "help" }
    return vim.tbl_filter(function(opt)
      return opt:match("^" .. vim.pesc(arg_lead))
    end, options)
  end

  -- Second argument for find
  if parts[2]:match("^f") then
    local types = { "s", "g", "c", "t", "e", "f", "i", "d", "a" }
    return vim.tbl_filter(function(t)
      return t:match("^" .. vim.pesc(arg_lead))
    end, types)
  end

  -- Second argument for db
  if parts[2] == "db" then
    local options = { "build", "show", "add", "rm" }
    return vim.tbl_filter(function(opt)
      return opt:match("^" .. vim.pesc(arg_lead))
    end, options)
  end

  return {}
end

return M
