---@mod cscope_dynamic Modern cscope integration for Neovim
---@brief [[
--- cscope_dynamic.nvim - A modern Neovim plugin for cscope with dynamic database updates
---
--- Features:
--- - Split database approach (big + small) for fast incremental updates
--- - Integration with fzf-lua, telescope, or quickfix
--- - Async database updates without blocking the editor
--- - Auto-detection of project root
--- - Support for both cscope and gtags-cscope
---@brief ]]

local M = {}

-- Default configuration
M.defaults = {
  -- Database files
  db_big = ".cscope.big",
  db_small = ".cscope.small",
  db_files_list = ".cscope.files",

  -- Auto-initialization
  auto_init = true,
  
  -- Adopt existing cscope.out if found (useful for pre-existing databases)
  adopt_existing_db = true,

  -- File patterns to index (for find command)
  file_patterns = { "*.c", "*.h", "*.cpp", "*.hpp", "*.cc", "*.hh", "*.cxx", "*.hxx" },

  -- Directories to search (relative to project root)
  src_dirs = { "." },

  -- Exclude patterns
  exclude_dirs = { ".git", "build", "node_modules", ".cache" },

  -- Executable paths (nil = auto-detect, or set explicit path)
  -- On Windows, set full path to avoid PowerShell alias conflicts
  -- Example: exec = "C:/tools/cscope/cscope.exe"
  exec = nil,           -- cscope executable (nil = "cscope")
  fd_exec = nil,        -- fd executable (nil = auto-detect "fd" or "fdfind")
  rg_exec = nil,        -- ripgrep executable (nil = "rg") - for future use
  
  -- File finder preference: "auto", "fd", "rg", "find", "powershell"
  -- "auto" tries fd -> rg -> find/powershell
  file_finder = "auto",

  -- Additional cscope arguments
  cscope_args = { "-q", "-k" }, -- -q for faster queries, -k for kernel mode (no /usr/include)

  -- Minimum interval between big database updates (seconds)
  big_update_interval = 60,

  -- Resolve symlinks
  resolve_links = true,

  -- Picker for results: "fzf-lua", "telescope", "quickfix", "loclist"
  picker = "fzf-lua",

  -- Picker options
  picker_opts = {
    fzf_lua = {
      winopts = {
        height = 0.6,
        width = 0.8,
        preview = {
          layout = "vertical",
          vertical = "down:50%",
        },
      },
    },
    telescope = {},
    quickfix = {
      open = true,
      position = "botright",
      height = 10,
    },
  },

  -- Keymaps
  disable_maps = false,
  prefix = "<leader>c",

  -- Status callbacks
  on_update_start = nil, -- function() ... end
  on_update_end = nil,   -- function() ... end

  -- Project root markers
  root_markers = { ".git", ".cscope.big", "cscope.out", "Makefile", "CMakeLists.txt" },

  -- Debug mode
  debug = false,
}

-- Plugin state
M.state = {
  initialized = false,
  updating = false,
  big_db_path = nil,
  small_db_path = nil,
  files_list_path = nil,
  project_root = nil,
  small_files = {}, -- files currently in small DB
  last_big_update = 0,
  jobs = {},
}

-- Configuration (will be populated by setup)
M.config = {}

-- Utility functions
local utils = require("cscope_dynamic.utils")
local db = require("cscope_dynamic.db")
local picker = require("cscope_dynamic.picker")

--- Log debug message
---@param msg string
local function log(msg)
  if M.config.debug then
    vim.notify("[cscope_dynamic] " .. msg, vim.log.levels.DEBUG)
  end
end

--- Find project root
---@return string|nil
local function find_project_root()
  local markers = M.config.root_markers
  local path = vim.fn.expand("%:p:h")

  while path and path ~= "/" do
    for _, marker in ipairs(markers) do
      local marker_path = path .. "/" .. marker
      if vim.fn.filereadable(marker_path) == 1 or vim.fn.isdirectory(marker_path) == 1 then
        return path
      end
    end
    path = vim.fn.fnamemodify(path, ":h")
  end

  return vim.fn.getcwd()
end

--- Initialize the plugin for the current project
---@param opts? table Optional override options
function M.init(opts)
  opts = opts or {}
  local root = opts.root or find_project_root()

  if not root then
    vim.notify("cscope_dynamic: Could not find project root", vim.log.levels.WARN)
    return false
  end

  M.state.project_root = root
  M.state.big_db_path = root .. "/" .. M.config.db_big
  M.state.small_db_path = root .. "/" .. M.config.db_small
  M.state.files_list_path = root .. "/" .. M.config.db_files_list

  log("Initializing with root: " .. root)

  -- Check if big DB exists
  local big_exists = vim.fn.filereadable(M.state.big_db_path) == 1

  if big_exists then
    -- Load existing databases
    M.load_databases()
    M.state.initialized = true
    log("Loaded existing databases")
  else
    -- Build initial database
    M.build_initial_db(function(success)
      if success then
        M.load_databases()
        M.state.initialized = true
        log("Initial database built successfully")
      else
        vim.notify("cscope_dynamic: Failed to build initial database", vim.log.levels.ERROR)
      end
    end)
  end

  return true
end

--- Mark databases as loaded (no vim cscope commands needed - we query directly)
function M.load_databases()
  local loaded = false

  if vim.fn.filereadable(M.state.big_db_path) == 1 then
    loaded = true
    log("Big DB available: " .. M.state.big_db_path)
  end

  if vim.fn.filereadable(M.state.small_db_path) == 1 then
    loaded = true
    log("Small DB available: " .. M.state.small_db_path)
  end

  return loaded
end

--- Build initial cscope database
---@param callback? function Callback when done
function M.build_initial_db(callback)
  if M.state.updating then
    log("Already updating, skipping")
    return
  end

  M.state.updating = true
  if M.config.on_update_start then
    M.config.on_update_start()
  end

  db.build_initial(M.config, M.state, function(success)
    M.state.updating = false
    M.state.last_big_update = os.time()

    if M.config.on_update_end then
      M.config.on_update_end()
    end

    if callback then
      callback(success)
    end
  end)
end

--- Update database for a specific file (moves to small DB)
---@param filepath string
function M.update_file(filepath)
  if not M.state.initialized then
    log("Not initialized, skipping update for: " .. filepath)
    return
  end

  -- Resolve to absolute path
  filepath = vim.fn.fnamemodify(filepath, ":p")

  -- Check if file matches patterns
  local matches = false
  for _, pattern in ipairs(M.config.file_patterns) do
    if vim.fn.fnamemodify(filepath, ":t"):match(utils.glob_to_pattern(pattern)) then
      matches = true
      break
    end
  end

  if not matches then
    log("File doesn't match patterns: " .. filepath)
    return
  end

  log("Updating file: " .. filepath)

  -- Add to small database
  db.update_small(M.config, M.state, filepath, function(success)
    if success then
      -- Reload databases
      M.load_databases()
      log("Updated small DB with: " .. filepath)
    end
  end)
end

--- Rebuild the entire database
---@param callback? function
function M.rebuild(callback)
  log("Rebuilding entire database")

  -- Remove existing databases
  vim.fn.delete(M.state.big_db_path)
  vim.fn.delete(M.state.small_db_path)
  vim.fn.delete(M.state.files_list_path)
  M.state.small_files = {}

  M.build_initial_db(callback)
end

--- Query cscope
---@param query_type string One of: s, g, c, t, e, f, i, d, a
---@param symbol string Symbol to search for
function M.query(query_type, symbol)
  if not M.state.initialized then
    vim.notify("cscope_dynamic: Not initialized. Run :CscopeInit first", vim.log.levels.WARN)
    return
  end

  -- Use word under cursor if no symbol provided
  if not symbol or symbol == "" then
    symbol = vim.fn.expand("<cword>")
  end

  if not symbol or symbol == "" then
    vim.notify("cscope_dynamic: No symbol under cursor", vim.log.levels.WARN)
    return
  end

  log("Query: " .. query_type .. " " .. symbol)

  -- Run cscope query
  local results = db.query(M.config, M.state, query_type, symbol)

  if not results or #results == 0 then
    vim.notify("cscope_dynamic: No results for '" .. symbol .. "'", vim.log.levels.INFO)
    return
  end

  -- Display results
  picker.show(M.config, results, query_type, symbol)
end

--- Get query type description
---@param query_type string
---@return string
function M.get_query_desc(query_type)
  local descriptions = {
    s = "Find this symbol",
    g = "Find global definition",
    c = "Find callers",
    t = "Find text string",
    e = "Find egrep pattern",
    f = "Find file",
    i = "Find files #including",
    d = "Find functions called by",
    a = "Find assignments to",
  }
  return descriptions[query_type] or "Unknown query type"
end

--- Resolve executable path (handles nil, validates existence)
---@param configured string|nil Configured path or nil for auto-detect
---@param fallbacks string[] List of names to try
---@return string|nil executable path or nil if not found
local function resolve_executable(configured, fallbacks)
  if configured then
    -- Explicit path configured - check if it exists
    if vim.fn.executable(configured) == 1 then
      return configured
    end
    -- Try as-is for full paths on Windows
    if vim.fn.filereadable(configured) == 1 then
      return configured
    end
    return nil
  end
  
  -- Auto-detect from fallbacks
  for _, name in ipairs(fallbacks) do
    if vim.fn.executable(name) == 1 then
      return name
    end
  end
  return nil
end

--- Setup the plugin
---@param opts? table Configuration options
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

  -- Resolve cscope executable
  local cscope_exec = resolve_executable(M.config.exec, { "cscope" })
  if not cscope_exec then
    local configured = M.config.exec or "cscope"
    vim.notify("cscope_dynamic: '" .. configured .. "' not found. Set config.exec to full path.", vim.log.levels.ERROR)
    return
  end
  M.config.exec = cscope_exec
  
  -- Resolve fd executable (optional, for file finding)
  M.config._fd_exec = resolve_executable(M.config.fd_exec, { "fd", "fdfind", "fd.exe" })
  
  -- Resolve rg executable (optional, for file finding) 
  M.config._rg_exec = resolve_executable(M.config.rg_exec, { "rg", "rg.exe" })
  
  log("Resolved executables - cscope: " .. M.config.exec .. 
      ", fd: " .. (M.config._fd_exec or "N/A") ..
      ", rg: " .. (M.config._rg_exec or "N/A"))

  -- Setup autocommands
  local group = vim.api.nvim_create_augroup("CscopeDynamic", { clear = true })

  -- Auto-init when entering a buffer
  if M.config.auto_init then
    vim.api.nvim_create_autocmd("BufEnter", {
      group = group,
      pattern = "*",
      callback = function()
        if not M.state.initialized then
          local root = find_project_root()
          if root and vim.fn.filereadable(root .. "/" .. M.config.db_big) == 1 then
            M.init({ root = root })
          end
        end
      end,
    })
  end

  -- Update on file save
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*",
    callback = function(ev)
      if M.state.initialized then
        M.update_file(ev.file)
      end
    end,
  })

  -- Setup keymaps
  if not M.config.disable_maps then
    require("cscope_dynamic.keymaps").setup(M.config.prefix)
  end

  -- Setup user commands
  require("cscope_dynamic.commands").setup()

  log("Setup complete")
end

--- Check if plugin is initialized
---@return boolean
function M.is_initialized()
  return M.state.initialized
end

--- Check if currently updating
---@return boolean
function M.is_updating()
  return M.state.updating
end

--- Get current project root
---@return string|nil
function M.get_root()
  return M.state.project_root
end

return M
