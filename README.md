# cscope_dynamic.nvim

A modern Neovim plugin for cscope with **dynamic database updates** and **fzf-lua integration**.

> Inspired by [erig0/cscope_dynamic](https://github.com/erig0/cscope_dynamic) and [joe-skb7/cscope-maps](https://github.com/joe-skb7/cscope-maps), modernized for Neovim with Lua.

## ✨ Features

- **Split Database Approach**: Uses two databases (big + small) for fast incremental updates
- **Async Updates**: Database updates happen in the background without blocking the editor
- **Modern Pickers**: Integration with fzf-lua, telescope, quickfix, or location list
- **Auto-initialization**: Automatically loads existing databases when entering a project
- **Smart File Tracking**: Tracks modified files and updates only the small database on save
- **Traditional Keymaps**: Compatible with classic cscope_maps.vim bindings
- **Full Query Support**: All cscope query types (symbol, definition, callers, etc.)

## 🔧 How the Split Database Works

Traditional cscope requires rebuilding the entire database when files change, which can be slow for large codebases. This plugin uses a clever approach:

1. **Big Database**: Contains most of your files, rebuilt less frequently
2. **Small Database**: Contains recently modified files, rebuilt on every save

When you save a file:
1. It's moved from the big database to the small database
2. Only the small database is rebuilt (often sub-second)
3. Queries search both databases automatically

This means you get instant updates while editing, with the option to periodically merge and rebuild the full database.

## 📦 Installation

### lazy.nvim

```lua
{
  "cristy-the-one/cscope_dynamic.nvim",
  dependencies = {
    "ibhagwan/fzf-lua",  -- optional, for fzf-lua picker
    -- "nvim-telescope/telescope.nvim",  -- optional, for telescope picker
  },
  ft = { "c", "cpp", "h", "hpp" },  -- lazy load for C/C++ files
  opts = {
    -- your config here (see Configuration section)
  },
}
```

### packer.nvim

```lua
use {
  "cristy-the-one/cscope_dynamic.nvim",
  requires = { "ibhagwan/fzf-lua" },
  config = function()
    require("cscope_dynamic").setup({
      -- your config here
    })
  end,
}
```

## ⚙️ Configuration

```lua
require("cscope_dynamic").setup({
  -- Database files (relative to project root)
  db_big = ".cscope.big",
  db_small = ".cscope.small",
  db_files_list = ".cscope.files",

  -- Auto-initialize when entering a project with existing database
  auto_init = true,
  
  -- Adopt existing cscope.out if found (useful for pre-built databases)
  adopt_existing_db = true,

  -- File patterns to index
  file_patterns = { "*.c", "*.h", "*.cpp", "*.hpp", "*.cc", "*.hh" },

  -- Source directories (relative to project root)
  src_dirs = { "." },

  -- Directories to exclude
  exclude_dirs = { ".git", "build", "node_modules", ".cache" },

  -- Executable paths (nil = auto-detect from PATH)
  -- Set explicit paths to avoid shell alias conflicts (especially on Windows/PowerShell)
  exec = nil,           -- cscope executable, e.g., "C:/tools/cscope.exe"
  fd_exec = nil,        -- fd executable, e.g., "C:/tools/fd.exe"
  rg_exec = nil,        -- ripgrep executable (for future use)
  
  -- File finder preference: "auto", "fd", "rg", "find", "powershell"
  -- "auto" tries: fd -> rg -> find (Unix) / powershell (Windows)
  file_finder = "auto",

  -- Additional cscope arguments
  cscope_args = { "-q", "-k" },

  -- Minimum interval between big database updates (seconds)
  big_update_interval = 60,

  -- Resolve symlinks
  resolve_links = true,

  -- Picker: "fzf-lua", "telescope", "quickfix", or "loclist"
  picker = "fzf-lua",

  -- Picker-specific options
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
    quickfix = {
      open = true,
      position = "botright",
      height = 10,
    },
  },

  -- Keymaps
  disable_maps = false,
  prefix = "<leader>c",

  -- Status callbacks (useful for statusline integration)
  on_update_start = function()
    vim.g.cscope_dynamic_updating = true
  end,
  on_update_end = function()
    vim.g.cscope_dynamic_updating = false
  end,

  -- Project root markers
  root_markers = { ".git", ".cscope.big", "cscope.out", "Makefile", "CMakeLists.txt" },

  -- Debug mode
  debug = false,
})
```

## ⌨️ Keymaps

Default keymaps (with `prefix = "<leader>c"`):

| Keymap | Description |
|--------|-------------|
| `<leader>cs` | Find symbol |
| `<leader>cg` | Find global definition |
| `<leader>cc` | Find callers |
| `<leader>ct` | Find text string |
| `<leader>ce` | Find egrep pattern |
| `<leader>cf` | Find file |
| `<leader>ci` | Find files #including |
| `<leader>cd` | Find called functions |
| `<leader>ca` | Find assignments |
| `<leader>cb` | Rebuild database |
| `<leader>cI` | Initialize database |
| `<leader>cS` | Show status |
| `<C-]>` | Find definition (falls back to tags) |

Traditional cscope_maps bindings are also available:

| Keymap | Description |
|--------|-------------|
| `<C-\>s` | Find symbol |
| `<C-\>g` | Find global definition |
| `<C-\>c` | Find callers |
| `<C-Space>s` | Find symbol (in split) |
| ... | etc. |

## 📋 Commands

```vim
" Main command (aliases: :Cs)
:Cscope find s <symbol>    " Find symbol
:Cscope find g <symbol>    " Find definition
:Cscope find c <symbol>    " Find callers
:Cscope find t <text>      " Find text
:Cscope find e <pattern>   " Find egrep pattern
:Cscope find f <file>      " Find file
:Cscope find i <file>      " Find includers
:Cscope find d <symbol>    " Find called by
:Cscope find a <symbol>    " Find assignments

" Short form
:Cs f g main               " Find definition of 'main'
:Cs f c printf             " Find callers of 'printf'

" Database management
:Cscope db build           " Rebuild database
:Cscope db show            " Show status

" Other commands
:CscopeInit                " Initialize database
:CscopeRebuild             " Rebuild database
:CscopeStatus              " Show detailed status
```

## 📊 Statusline Integration

You can add a cscope indicator to your statusline:

```lua
-- lualine example
require("lualine").setup({
  sections = {
    lualine_x = {
      {
        function()
          if vim.g.cscope_dynamic_updating then
            return "󰄷 CS"
          end
          return ""
        end,
        color = { fg = "#ff9e64" },
      },
    },
  },
})
```

## 🔄 Workflow

1. **First time in a project**: Run `:CscopeInit` or press `<leader>cI` to build the initial database
2. **Edit files normally**: The database updates automatically when you save
3. **Query as needed**: Use any of the keymaps or commands to search
4. **Periodic rebuild**: Optionally run `:CscopeRebuild` to merge small changes back to big database

## 🪟 Windows Setup

The plugin works on Windows with some additional setup:

### Prerequisites

1. **Install cscope for Windows**: Download from [cscope-win32](https://code.google.com/archive/p/cscope-win32/) or build from source
2. **Install fd** (recommended): `winget install sharkdp.fd` or `scoop install fd`

### Configuration for Windows

PowerShell aliases can shadow executables. Specify full paths to avoid conflicts:

```lua
require("cscope_dynamic").setup({
  -- Full paths to avoid PowerShell alias conflicts
  exec = "C:/tools/cscope/cscope.exe",
  fd_exec = "C:/Users/YourName/scoop/shims/fd.exe",  -- if installed via scoop
  -- Or if fd is in PATH and not aliased:
  -- fd_exec = "fd.exe",
  
  -- Use fd explicitly (skip auto-detection)
  file_finder = "fd",
  
  -- Adopt pre-existing databases created from command line
  adopt_existing_db = true,
})
```

### Finding Your Executable Paths

In PowerShell:
```powershell
# Find where fd.exe actually is (not the alias)
Get-Command fd.exe | Select-Object Source

# Or for cscope
Get-Command cscope.exe | Select-Object Source
```

### Troubleshooting

Run `:CscopeDebug` to see:
- Detected platform
- Resolved executable paths
- Which file finder is being used
- Existing database files
- File finding test results

## 🆚 Comparison with Other Plugins

| Feature | cscope_dynamic.nvim | cscope_maps.nvim | Original cscope_dynamic |
|---------|---------------------|------------------|------------------------|
| Split database | ✅ | ❌ | ✅ |
| Async updates | ✅ | ✅ | ❌ (uses CursorHold) |
| fzf-lua support | ✅ | ✅ | ❌ |
| telescope support | ✅ | ✅ | ❌ |
| Written in Lua | ✅ | ✅ | ❌ (VimScript) |
| Neovim only | ✅ | ✅ | ❌ |
| Traditional keymaps | ✅ | ✅ | ❌ |
| Windows support | ✅ | ✅ | ❌ |
| Adopt existing DB | ✅ | ✅ | ❌ |

## 🤝 Related Projects

- [dhananjaylatkar/cscope_maps.nvim](https://github.com/dhananjaylatkar/cscope_maps.nvim) - Modern cscope support (no split DB)
- [erig0/cscope_dynamic](https://github.com/erig0/cscope_dynamic) - Original split database plugin (VimScript)
- [joe-skb7/cscope-maps](https://github.com/joe-skb7/cscope-maps) - Traditional cscope keymaps

## 📄 License

MIT
