-- cscope_dynamic.nvim - Plugin entry point
-- This file is auto-loaded by Neovim from plugin/

if vim.g.loaded_cscope_dynamic then
  return
end
vim.g.loaded_cscope_dynamic = true

-- Check Neovim version
if vim.fn.has("nvim-0.8") == 0 then
  vim.notify("cscope_dynamic.nvim requires Neovim 0.8+", vim.log.levels.ERROR)
  return
end

-- Global statusline indicator
vim.g.cscope_dynamic_updating = false
