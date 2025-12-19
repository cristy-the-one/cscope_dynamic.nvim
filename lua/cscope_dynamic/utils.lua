---@mod cscope_dynamic.utils Utility functions
local M = {}

--- Check if running on Windows
---@return boolean
function M.is_windows()
  return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

--- Get path separator for current OS
---@return string
function M.path_sep()
  return M.is_windows() and "\\" or "/"
end

--- Normalize path separators (always use forward slash internally)
---@param path string
---@return string
function M.normalize_path(path)
  return path:gsub("\\", "/")
end

--- Convert to OS-native path separators
---@param path string
---@return string
function M.native_path(path)
  if M.is_windows() then
    return path:gsub("/", "\\")
  end
  return path
end

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
  if M.is_windows() then
    -- Windows: use double quotes, escape internal double quotes
    -- Also handle paths with spaces
    if str:match('[%s"^&|<>%%]') then
      return '"' .. str:gsub('"', '""') .. '"'
    end
    return str
  end
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

  -- On Windows, might need to run through cmd.exe or powershell
  local shell_cmd = cmd
  if M.is_windows() and opts.use_powershell then
    shell_cmd = 'powershell -NoProfile -Command "' .. cmd:gsub('"', '\\"') .. '"'
  end

  local job_id = vim.fn.jobstart(shell_cmd, {
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

--- Run sync command with timeout (safe on Windows)
---@param cmd string|table
---@param opts? table
---@return boolean, string[], string[]
function M.sync_cmd(cmd, opts)
  opts = opts or {}
  local timeout_ms = opts.timeout or 10000  -- 10 second default

  if type(cmd) == "table" then
    cmd = table.concat(cmd, " ")
  end

  local result = {}
  local stderr = {}
  local done = false
  local exit_code = -1

  local job_id = vim.fn.jobstart(cmd, {
    cwd = opts.cwd,
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(result, line)
        end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stderr, line)
        end
      end
    end,
    on_exit = function(_, code)
      exit_code = code
      done = true
    end,
  })

  if job_id <= 0 then
    return false, {}, {"Failed to start job: " .. cmd}
  end

  -- Wait with timeout
  local waited = 0
  local interval = 50
  while not done and waited < timeout_ms do
    vim.wait(interval, function() return done end)
    waited = waited + interval
  end

  if not done then
    pcall(vim.fn.jobstop, job_id)
    return false, result, {"Command timed out after " .. timeout_ms .. "ms"}
  end

  return exit_code == 0, result, stderr
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
  -- Normalize both paths for comparison
  local norm_path = M.normalize_path(path)
  local norm_base = M.normalize_path(base)
  
  -- Ensure base doesn't end with separator
  norm_base = norm_base:gsub("/$", "")
  
  if norm_path:sub(1, #norm_base) == norm_base then
    local rel = norm_path:sub(#norm_base + 1)
    if rel:sub(1, 1) == "/" then
      rel = rel:sub(2)
    end
    return rel
  end
  return path
end

--- Check if path is absolute
---@param path string
---@return boolean
function M.is_absolute_path(path)
  if M.is_windows() then
    -- Windows: C:\... or \\server\... or /...
    return path:match("^%a:") or path:match("^\\\\") or path:match("^/")
  end
  return path:match("^/")
end

--- Join paths
---@param ... string
---@return string
function M.path_join(...)
  local parts = {...}
  local result = table.concat(parts, "/")
  -- Normalize multiple slashes
  result = result:gsub("//+", "/")
  return result
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
  
  -- Normalize for comparison
  local norm_remove = M.normalize_path(line_to_remove)

  local new_lines = {}
  for _, line in ipairs(lines) do
    local norm_line = M.normalize_path(line)
    if norm_line ~= norm_remove then
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
      filename = M.normalize_path(file),
      func = func,
      lnum = tonumber(lnum),
      text = context or "",
    }
  end

  -- Try alternative format: file:line context
  file, lnum, context = line:match("^([^:]+):(%d+)%s*(.*)$")
  if file and lnum then
    return {
      filename = M.normalize_path(file),
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
  local finder = config.file_finder or "auto"
  
  -- Normalize root path
  local search_root = M.normalize_path(root)
  
  -- Build extension list and exclude list (used by multiple finders)
  local extensions = {}
  for _, pattern in ipairs(config.file_patterns) do
    local ext = pattern:match("^%*%.(.+)$")
    if ext then
      table.insert(extensions, ext)
    end
  end
  
  -- Try fd first (auto or explicit)
  if finder == "auto" or finder == "fd" then
    local fd_exec = config._fd_exec
    if fd_exec then
      local ext_args = {}
      for _, ext in ipairs(extensions) do
        table.insert(ext_args, "-e " .. ext)
      end
      
      local exclude_args = {}
      for _, dir in ipairs(config.exclude_dirs) do
        table.insert(exclude_args, "-E " .. dir)
      end
      
      return fd_exec .. " --type f " .. 
             table.concat(ext_args, " ") .. " " .. 
             table.concat(exclude_args, " ") .. 
             " . " .. M.shell_escape(search_root)
    elseif finder == "fd" then
      vim.notify("cscope_dynamic: fd not found, falling back", vim.log.levels.WARN)
    end
  end
  
  -- Try ripgrep (auto or explicit)
  if finder == "auto" or finder == "rg" then
    local rg_exec = config._rg_exec
    if rg_exec then
      local type_args = {}
      for _, ext in ipairs(extensions) do
        table.insert(type_args, "-g '*." .. ext .. "'")
      end
      
      local exclude_args = {}
      for _, dir in ipairs(config.exclude_dirs) do
        table.insert(exclude_args, "-g '!" .. dir .. "/*'")
      end
      
      return rg_exec .. " --files " ..
             table.concat(type_args, " ") .. " " ..
             table.concat(exclude_args, " ") .. " " ..
             M.shell_escape(search_root)
    elseif finder == "rg" then
      vim.notify("cscope_dynamic: rg not found, falling back", vim.log.levels.WARN)
    end
  end
  
  -- Windows: use PowerShell if no fd/rg
  if M.is_windows() and (finder == "auto" or finder == "powershell") then
    local include_patterns = {}
    for _, ext in ipairs(extensions) do
      table.insert(include_patterns, '"*.' .. ext .. '"')
    end
    
    local exclude_patterns = {}
    for _, dir in ipairs(config.exclude_dirs) do
      table.insert(exclude_patterns, dir)
    end
    
    -- PowerShell command to find files
    -- Use -LiteralPath for paths with special chars
    local ps_script = string.format(
      [[Get-ChildItem -LiteralPath '%s' -Recurse -File -Include %s | Where-Object { $exclude = @(%s); $dominated = $false; foreach ($e in $exclude) { if ($_.FullName -like "*\$e\*") { $dominated = $true; break } }; -not $dominated } | ForEach-Object { $_.FullName }]],
      search_root:gsub("'", "''"),
      table.concat(include_patterns, ","),
      '"' .. table.concat(exclude_patterns, '","') .. '"'
    )
    
    return 'powershell -NoProfile -Command "' .. ps_script:gsub('"', '\\"') .. '"'
  end
  
  -- Unix: use find
  if not M.is_windows() and (finder == "auto" or finder == "find") then
    local exclude_parts = {}
    for _, exclude in ipairs(config.exclude_dirs) do
      table.insert(exclude_parts, "-path '*/" .. exclude .. "/*'")
    end
    
    local name_parts = {}
    for _, pattern in ipairs(config.file_patterns) do
      table.insert(name_parts, "-name '" .. pattern .. "'")
    end
    
    local cmd = "find " .. M.shell_escape(search_root) .. " -type f"
    
    if #name_parts > 0 then
      cmd = cmd .. " \\( " .. table.concat(name_parts, " -o ") .. " \\)"
    end
    
    for _, excl in ipairs(exclude_parts) do
      cmd = cmd .. " ! " .. excl
    end
    
    return cmd
  end
  
  -- Fallback error
  vim.notify("cscope_dynamic: No suitable file finder available. Install fd or rg.", vim.log.levels.ERROR)
  return "echo 'No file finder available'"
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
