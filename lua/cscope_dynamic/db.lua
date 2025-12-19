---@mod cscope_dynamic.db Database management
---@brief [[
--- Manages the split database approach:
--- - Big DB: Contains most files, rebuilt less frequently
--- - Small DB: Contains recently modified files, rebuilt on save
---@brief ]]

local M = {}
local utils = require("cscope_dynamic.utils")

--- Build initial (big) database
---@param config table
---@param state table
---@param callback function
function M.build_initial(config, state, callback)
  local root = state.project_root

  -- Generate file list
  local find_cmd = utils.make_find_cmd(config, root)
  
  -- Debug: show command
  if config.debug then
    vim.schedule(function()
      vim.notify("cscope_dynamic: Running: " .. find_cmd, vim.log.levels.DEBUG)
    end)
  end

  utils.async_cmd(find_cmd, { cwd = root }, function(success, files, stderr)
    if not success then
      vim.schedule(function()
        vim.notify("cscope_dynamic: Find command failed: " .. table.concat(stderr or {}, "\n"), vim.log.levels.ERROR)
        callback(false)
      end)
      return
    end
    
    if #files == 0 then
      vim.schedule(function()
        vim.notify("cscope_dynamic: No source files found in " .. root, vim.log.levels.WARN)
        vim.notify("cscope_dynamic: Command was: " .. find_cmd, vim.log.levels.DEBUG)
        callback(false)
      end)
      return
    end

    -- Resolve symlinks if configured
    if config.resolve_links then
      local resolved = {}
      for _, file in ipairs(files) do
        local real = vim.fn.resolve(file)
        table.insert(resolved, real)
      end
      files = resolved
    end

    -- Write file list
    local list_written = utils.write_lines(state.files_list_path, files)
    if not list_written then
      vim.schedule(function()
        vim.notify("cscope_dynamic: Failed to write file list", vim.log.levels.ERROR)
        callback(false)
      end)
      return
    end

    -- Build cscope database
    local cscope_args = {
      config.exec,
      "-b", -- Build database
      "-i", utils.shell_escape(state.files_list_path),
      "-f", utils.shell_escape(state.big_db_path),
    }

    -- Add user-specified args
    for _, arg in ipairs(config.cscope_args) do
      table.insert(cscope_args, arg)
    end

    local cmd = table.concat(cscope_args, " ")

    utils.async_cmd(cmd, { cwd = root }, function(build_success, _, stderr)
      vim.schedule(function()
        if build_success then
          vim.notify("cscope_dynamic: Database built (" .. #files .. " files)", vim.log.levels.INFO)
          callback(true)
        else
          vim.notify("cscope_dynamic: Build failed: " .. table.concat(stderr, "\n"), vim.log.levels.ERROR)
          callback(false)
        end
      end)
    end)
  end)
end

--- Update small database with a single file
---@param config table
---@param state table
---@param filepath string
---@param callback function
function M.update_small(config, state, filepath, callback)
  local root = state.project_root

  -- Get relative path
  local rel_path = utils.relative_path(filepath, root)
  if rel_path == filepath then
    -- File is not under project root
    callback(false)
    return
  end

  -- Resolve symlink if configured
  if config.resolve_links then
    filepath = vim.fn.resolve(filepath)
    rel_path = utils.relative_path(filepath, root)
  end

  -- Track file in small database
  if not vim.tbl_contains(state.small_files, rel_path) then
    table.insert(state.small_files, rel_path)

    -- Remove from big database files list (to avoid duplicates)
    utils.remove_line(state.files_list_path, rel_path)
    utils.remove_line(state.files_list_path, filepath)
  end

  -- Write small files list
  local small_list_path = state.small_db_path .. ".files"
  utils.write_lines(small_list_path, state.small_files)

  -- Build small database
  local cscope_args = {
    config.exec,
    "-b",
    "-i", utils.shell_escape(small_list_path),
    "-f", utils.shell_escape(state.small_db_path),
  }

  for _, arg in ipairs(config.cscope_args) do
    table.insert(cscope_args, arg)
  end

  local cmd = table.concat(cscope_args, " ")

  utils.async_cmd(cmd, { cwd = root }, function(success)
    vim.schedule(function()
      callback(success)
    end)
  end)
end

--- Merge small database back into big database
---@param config table
---@param state table
---@param callback function
function M.merge_databases(config, state, callback)
  if #state.small_files == 0 then
    callback(true)
    return
  end

  local root = state.project_root

  -- Read current big file list
  local files = utils.read_lines(state.files_list_path) or {}

  -- Add small files back
  for _, file in ipairs(state.small_files) do
    if not vim.tbl_contains(files, file) then
      table.insert(files, file)
    end
  end

  -- Write merged list
  utils.write_lines(state.files_list_path, files)

  -- Clear small files tracking
  state.small_files = {}

  -- Remove small database
  vim.fn.delete(state.small_db_path)
  vim.fn.delete(state.small_db_path .. ".files")
  vim.fn.delete(state.small_db_path .. ".in")
  vim.fn.delete(state.small_db_path .. ".po")

  -- Rebuild big database
  local cscope_args = {
    config.exec,
    "-b",
    "-i", utils.shell_escape(state.files_list_path),
    "-f", utils.shell_escape(state.big_db_path),
  }

  for _, arg in ipairs(config.cscope_args) do
    table.insert(cscope_args, arg)
  end

  local cmd = table.concat(cscope_args, " ")

  utils.async_cmd(cmd, { cwd = root }, function(success)
    vim.schedule(function()
      if success then
        state.last_big_update = os.time()
      end
      callback(success)
    end)
  end)
end

--- Query cscope database
---@param config table
---@param state table
---@param query_type string
---@param symbol string
---@return table[]
function M.query(config, state, query_type, symbol)
  local root = state.project_root
  local results = {}

  -- Map query type to cscope number
  local query_map = {
    s = "0", -- Find symbol
    g = "1", -- Find global definition
    c = "3", -- Find callers
    t = "4", -- Find text string
    e = "6", -- Find egrep pattern
    f = "7", -- Find file
    i = "8", -- Find files including
    d = "2", -- Find functions called by
    a = "9", -- Find assignments
  }

  local query_num = query_map[query_type]
  if not query_num then
    vim.notify("cscope_dynamic: Invalid query type: " .. query_type, vim.log.levels.ERROR)
    return {}
  end

  -- Query both databases
  local dbs = {}
  if utils.file_exists(state.big_db_path) then
    table.insert(dbs, state.big_db_path)
  end
  if utils.file_exists(state.small_db_path) then
    table.insert(dbs, state.small_db_path)
  end

  for _, db_path in ipairs(dbs) do
    local cmd = string.format(
      "%s -d -f %s -L -%s %s",
      config.exec,
      utils.shell_escape(db_path),
      query_num,
      utils.shell_escape(symbol)
    )

    local success, output = utils.sync_cmd(cmd, { cwd = root })

    if success then
      for _, line in ipairs(output) do
        local parsed = utils.parse_cscope_line(line)
        if parsed then
          -- Make path relative to root for display
          parsed.display_path = utils.relative_path(parsed.filename, root)

          -- Resolve to absolute for jumping
          if not utils.is_absolute_path(parsed.filename) then
            parsed.filename = utils.path_join(root, parsed.filename)
          end

          table.insert(results, parsed)
        end
      end
    end
  end

  -- Remove duplicates (same file:line)
  local seen = {}
  local unique = {}
  for _, result in ipairs(results) do
    local key = result.filename .. ":" .. result.lnum
    if not seen[key] then
      seen[key] = true
      table.insert(unique, result)
    end
  end

  return unique
end

--- Get database status
---@param state table
---@return table
function M.status(state)
  local status = {
    initialized = state.initialized,
    updating = state.updating,
    project_root = state.project_root,
    big_db_exists = state.big_db_path and utils.file_exists(state.big_db_path),
    small_db_exists = state.small_db_path and utils.file_exists(state.small_db_path),
    small_files_count = #state.small_files,
    last_big_update = state.last_big_update,
  }

  -- Get file counts
  if status.big_db_exists and state.files_list_path then
    local files = utils.read_lines(state.files_list_path)
    status.big_files_count = files and #files or 0
  else
    status.big_files_count = 0
  end

  return status
end

return M
