---@mod cscope_dynamic.utils Utility functions
local M = {}

--- Convert glob pattern to Lua pattern
---@param glob string
---@return string
function M.glob_to_pattern(glob)
  local pattern = glob:gsub("%.", "%%.")
  pattern = pattern:gsub("%*", ".*")
  pattern = pattern:gsub("%?", ".")
  return "^" .. pattern .. "$"
end

--- Escape string for shell
---@param str string
---@return string
function M.shell_escape(str)
  return vim.fn.shellescape(str)
end

--- Run async command
---@param cmd string|table
---@param opts? table
---@param callback function
function M.async_cmd(cmd, opts, callback)
  opts = opts or {}

  if type(cmd) == "table" then
    cmd = table.concat(cmd, " ")
  end

  local stdout_data = {}
  local stderr_data = {}

  local job_id = vim.fn.jobstart(cmd, {
    cwd = opts.cwd,
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stdout_data, line)
        end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stderr_data, line)
        end
      end
    end,
    on_exit = function(_, code)
      callback(code == 0, stdout_data, stderr_data)
    end,
  })

  return job_id
end

--- Run sync command with timeout
---@param cmd string|table
---@param opts? table
---@return boolean, string[], string[]
function M.sync_cmd(cmd, opts)
  opts = opts or {}

  if type(cmd) == "table" then
    cmd = table.concat(cmd, " ")
  end

  local result = vim.fn.systemlist(cmd)
  local success = vim.v.shell_error == 0

  return success, result, {}
end

--- Check if file exists
---@param path string
---@return boolean
function M.file_exists(path)
  return vim.fn.filereadable(path) == 1
end

--- Check if directory exists
---@param path string
---@return boolean
function M.dir_exists(path)
  return vim.fn.isdirectory(path) == 1
end

--- Get relative path
---@param path string
---@param base string
---@return string
function M.relative_path(path, base)
  if path:sub(1, #base) == base then
    local rel = path:sub(#base + 1)
    if rel:sub(1, 1) == "/" then
      rel = rel:sub(2)
    end
    return rel
  end
  return path
end

--- Read file lines
---@param path string
---@return string[]|nil
function M.read_lines(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local lines = {}
  for line in file:lines() do
    table.insert(lines, line)
  end

  file:close()
  return lines
end

--- Write file lines
---@param path string
---@param lines string[]
---@return boolean
function M.write_lines(path, lines)
  local file = io.open(path, "w")
  if not file then
    return false
  end

  for _, line in ipairs(lines) do
    file:write(line .. "\n")
  end

  file:close()
  return true
end

--- Append line to file
---@param path string
---@param line string
---@return boolean
function M.append_line(path, line)
  local file = io.open(path, "a")
  if not file then
    return false
  end

  file:write(line .. "\n")
  file:close()
  return true
end

--- Remove line from file
---@param path string
---@param line_to_remove string
---@return boolean
function M.remove_line(path, line_to_remove)
  local lines = M.read_lines(path)
  if not lines then
    return false
  end

  local new_lines = {}
  for _, line in ipairs(lines) do
    if line ~= line_to_remove then
      table.insert(new_lines, line)
    end
  end

  return M.write_lines(path, new_lines)
end

--- Parse cscope line format
--- Format: <file> <function> <line> <context>
---@param line string
---@return table|nil
function M.parse_cscope_line(line)
  -- Try standard cscope output format: file function line context
  local file, func, lnum, context = line:match("^(%S+)%s+(%S+)%s+(%d+)%s+(.*)$")

  if file and func and lnum then
    return {
      filename = file,
      func = func,
      lnum = tonumber(lnum),
      text = context or "",
    }
  end

  -- Try alternative format: file:line context
  file, lnum, context = line:match("^([^:]+):(%d+)%s*(.*)$")
  if file and lnum then
    return {
      filename = file,
      func = "",
      lnum = tonumber(lnum),
      text = context or "",
    }
  end

  return nil
end

--- Create find command for source files
---@param config table
---@param root string
---@return string
function M.make_find_cmd(config, root)
  -- Prefer fd/fdfind if available (simpler and faster)
  local fd_cmd = nil
  if vim.fn.executable("fd") == 1 then
    fd_cmd = "fd"
  elseif vim.fn.executable("fdfind") == 1 then
    fd_cmd = "fdfind"
  end
  
  if fd_cmd then
    -- fd is much simpler
    local extensions = {}
    for _, pattern in ipairs(config.file_patterns) do
      -- Convert *.c to c
      local ext = pattern:match("^%*%.(.+)$")
      if ext then
        table.insert(extensions, "-e " .. ext)
      end
    end
    
    local excludes = {}
    for _, dir in ipairs(config.exclude_dirs) do
      table.insert(excludes, "-E " .. dir)
    end
    
    return fd_cmd .. " --type f " .. table.concat(extensions, " ") .. " " .. table.concat(excludes, " ") .. " . " .. M.shell_escape(root)
  end
  
  -- Fallback to find
  -- Build exclude args
  local exclude_parts = {}
  for _, exclude in ipairs(config.exclude_dirs) do
    table.insert(exclude_parts, "-path '*/" .. exclude .. "/*'")
  end
  
  -- Build name patterns
  local name_parts = {}
  for _, pattern in ipairs(config.file_patterns) do
    table.insert(name_parts, "-name '" .. pattern .. "'")
  end
  
  -- Simpler find command
  local cmd = "find " .. M.shell_escape(root) .. " -type f"
  
  -- Add name filters with OR
  if #name_parts > 0 then
    cmd = cmd .. " \\( " .. table.concat(name_parts, " -o ") .. " \\)"
  end
  
  -- Add excludes
  for _, excl in ipairs(exclude_parts) do
    cmd = cmd .. " ! " .. excl
  end
  
  return cmd
end

--- Debounce function
---@param fn function
---@param ms number
---@return function
function M.debounce(fn, ms)
  local timer = nil
  return function(...)
    local args = { ... }
    if timer then
      timer:stop()
      timer:close()
    end
    timer = vim.loop.new_timer()
    timer:start(ms, 0, vim.schedule_wrap(function()
      timer:close()
      timer = nil
      fn(unpack(args))
    end))
  end
end

--- Throttle function
---@param fn function
---@param ms number
---@return function
function M.throttle(fn, ms)
  local last_call = 0
  local timer = nil

  return function(...)
    local args = { ... }
    local now = vim.loop.now()

    if now - last_call >= ms then
      last_call = now
      fn(unpack(args))
    elseif not timer then
      timer = vim.loop.new_timer()
      timer:start(ms - (now - last_call), 0, vim.schedule_wrap(function()
        timer:close()
        timer = nil
        last_call = vim.loop.now()
        fn(unpack(args))
      end))
    end
  end
end

return M
