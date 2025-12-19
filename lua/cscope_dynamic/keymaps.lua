---@mod cscope_dynamic.keymaps Keymap setup
---@brief [[
--- Provides keymaps similar to traditional cscope_maps.vim
--- with modern fzf-lua integration
---@brief ]]

local M = {}

--- Setup keymaps
---@param prefix string Key prefix for all mappings
function M.setup(prefix)
  local cscope = require("cscope_dynamic")

  -- Query keymaps
  local queries = {
    { key = "s", type = "s", desc = "Find symbol" },
    { key = "g", type = "g", desc = "Find global definition" },
    { key = "c", type = "c", desc = "Find callers" },
    { key = "t", type = "t", desc = "Find text string" },
    { key = "e", type = "e", desc = "Find egrep pattern" },
    { key = "f", type = "f", desc = "Find file" },
    { key = "i", type = "i", desc = "Find files #including" },
    { key = "d", type = "d", desc = "Find called functions" },
    { key = "a", type = "a", desc = "Find assignments" },
  }

  for _, q in ipairs(queries) do
    vim.keymap.set("n", prefix .. q.key, function()
      cscope.query(q.type, vim.fn.expand("<cword>"))
    end, { desc = "Cscope: " .. q.desc })

    -- Visual mode: use selected text
    vim.keymap.set("v", prefix .. q.key, function()
      local start_pos = vim.fn.getpos("'<")
      local end_pos = vim.fn.getpos("'>")
      local lines = vim.fn.getregion(start_pos, end_pos, { type = vim.fn.mode() })
      local text = table.concat(lines, " ")
      text = text:gsub("^%s+", ""):gsub("%s+$", "")
      cscope.query(q.type, text)
    end, { desc = "Cscope: " .. q.desc })
  end

  -- Database management keymaps
  vim.keymap.set("n", prefix .. "b", function()
    cscope.rebuild(function(success)
      if success then
        vim.notify("cscope_dynamic: Database rebuilt", vim.log.levels.INFO)
      end
    end)
  end, { desc = "Cscope: Rebuild database" })

  vim.keymap.set("n", prefix .. "I", function()
    cscope.init()
  end, { desc = "Cscope: Initialize" })

  -- Status
  vim.keymap.set("n", prefix .. "S", function()
    local db = require("cscope_dynamic.db")
    local status = db.status(cscope.state)

    local lines = {
      "Cscope Dynamic Status:",
      "  Initialized: " .. tostring(status.initialized),
      "  Updating: " .. tostring(status.updating),
      "  Project root: " .. (status.project_root or "N/A"),
      "  Big DB exists: " .. tostring(status.big_db_exists),
      "  Small DB exists: " .. tostring(status.small_db_exists),
      "  Files in big DB: " .. status.big_files_count,
      "  Files in small DB: " .. status.small_files_count,
    }

    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end, { desc = "Cscope: Show status" })

  -- Ctrl+] replacement for :cstag functionality
  vim.keymap.set("n", "<C-]>", function()
    local symbol = vim.fn.expand("<cword>")
    if symbol and symbol ~= "" then
      -- Try cscope first
      local results = require("cscope_dynamic.db").query(
        cscope.config,
        cscope.state,
        "g",
        symbol
      )

      if #results > 0 then
        require("cscope_dynamic.picker").show(cscope.config, results, "g", symbol)
      else
        -- Fall back to ctags
        pcall(function()
          vim.cmd("tag " .. symbol)
        end)
      end
    end
  end, { desc = "Cscope: Find definition or tag" })

  -- Additional Ctrl+\ bindings (traditional cscope_maps style)
  local ctrl_slash_maps = {
    { key = "s", type = "s" },
    { key = "g", type = "g" },
    { key = "c", type = "c" },
    { key = "t", type = "t" },
    { key = "e", type = "e" },
    { key = "f", type = "f" },
    { key = "i", type = "i" },
    { key = "d", type = "d" },
    { key = "a", type = "a" },
  }

  for _, m in ipairs(ctrl_slash_maps) do
    vim.keymap.set("n", "<C-\\>" .. m.key, function()
      cscope.query(m.type, vim.fn.expand("<cword>"))
    end, { desc = "Cscope: " .. cscope.get_query_desc(m.type) })
  end

  -- Ctrl+Space for horizontal split versions (opens in split)
  for _, m in ipairs(ctrl_slash_maps) do
    vim.keymap.set("n", "<C-Space>" .. m.key, function()
      vim.cmd("split")
      cscope.query(m.type, vim.fn.expand("<cword>"))
    end, { desc = "Cscope (split): " .. cscope.get_query_desc(m.type) })
  end

  -- Register with which-key if available
  pcall(function()
    local wk = require("which-key")
    wk.add({
      { prefix, group = "Cscope" },
      { prefix .. "s", desc = "Find symbol" },
      { prefix .. "g", desc = "Find global definition" },
      { prefix .. "c", desc = "Find callers" },
      { prefix .. "t", desc = "Find text string" },
      { prefix .. "e", desc = "Find egrep pattern" },
      { prefix .. "f", desc = "Find file" },
      { prefix .. "i", desc = "Find files #including" },
      { prefix .. "d", desc = "Find called functions" },
      { prefix .. "a", desc = "Find assignments" },
      { prefix .. "b", desc = "Rebuild database" },
      { prefix .. "I", desc = "Initialize" },
      { prefix .. "S", desc = "Show status" },
    })
  end)
end

return M
