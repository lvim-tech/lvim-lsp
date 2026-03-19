# lvim-lsp

LSP manager for Neovim. Manages the lifecycle of LSP servers, EFM tools, DAP adapters, and Mason installations without third-party config files.

Requires [`lvim-utils`](https://github.com/lvim-tech/lvim-utils) for UI components.

---

## Installation

```lua
-- lazy.nvim
{
    "lvim-tech/lvim-lsp",
    dependencies = { "lvim-tech/lvim-utils", "williamboman/mason.nvim" },
    config = function()
        require("lvim-lsp").setup({ ... })
    end,
}
```

---

## Quick start

```lua
require("lvim-lsp").setup({
    file_types = {
        lua_ls = {
            filetypes  = { "lua" },
            lsp        = { "lua-language-server" },
            formatters = { "stylua" },
        },
        tsserver = {
            filetypes = { "typescript", "javascript", "typescriptreact" },
            lsp       = { "typescript-language-server" },
        },
        rust_analyzer = {
            filetypes = { "rust" },
            lsp       = { "rust-analyzer" },
        },
    },
    server_config_dirs = { "my_config.lsp.servers" },
})
```

---

## Configuration

All values are optional except `file_types` and `server_config_dirs`.

```lua
require("lvim-lsp").setup({

    -- REQUIRED ---------------------------------------------------------------

    -- Maps server_key → entry.
    -- Determines which servers start for which filetypes.
    -- Each tool can be a plain string "mason-pkg" or a table
    -- { "mason-pkg", bin = "binary" } when the installed binary name
    -- differs from the Mason package name.
    file_types = {
        lua_ls = {
            filetypes  = { "lua" },
            lsp        = { "lua-language-server" },
            formatters = { "stylua" },
        },
        tsserver = {
            filetypes = { "typescript", "javascript" },
            lsp       = { "typescript-language-server" },
        },
        go = {
            filetypes  = { "go", "gomod" },
            lsp        = { "gopls" },
            debuggers  = { { "delve", bin = "dlv" } },
        },
    },

    -- Lua require prefixes searched in order for server config modules.
    -- First match wins.
    server_config_dirs = { "my_config.lsp.servers" },

    -- CALLBACKS --------------------------------------------------------------

    -- Called for every LSP client after attach.
    on_attach = function(client, bufnr) end,

    -- Called after DirChanged (after old-project servers are stopped).
    -- Useful for fidget.nvim clear or similar.
    on_dir_change = function() end,

    -- TIMING -----------------------------------------------------------------

    -- Delay (ms) before autocommands are registered on startup.
    startup_delay_ms = 100,

    -- Delay (ms) after DirChanged before old-project servers are stopped.
    dir_change_delay_ms = 5000,

    -- EFM --------------------------------------------------------------------

    efm = {
        -- Filetypes EFM should handle even without a registered tool config.
        filetypes = {},
        -- Executable used for PATH checks.
        executable = "efm-langserver",
    },

    -- FEATURES ---------------------------------------------------------------

    features = {
        -- Automatically highlight the symbol under the cursor on CursorHold.
        document_highlight = false,

        -- Automatically format on save (BufWritePre).
        -- Can be true/false or function()->boolean.
        -- Can be overridden per-project via .lvim-lsp.lua.
        auto_format = false,

        -- Inlay hints (Neovim 0.10+).
        -- Can be true/false or function()->boolean.
        -- Can be overridden per-project via .lvim-lsp.lua.
        inlay_hints = false,
    },

    -- CODE LENS --------------------------------------------------------------

    code_lens = {
        -- Refresh on LspAttach / TextChanged.
        -- Double-click on a lens → execute it.
        -- When false — codelens functions are silenced entirely.
        enabled = false,
    },

    -- DIAGNOSTICS ------------------------------------------------------------

    diagnostics = {
        -- Title of the diagnostics popup.
        popup_title = " Diagnostics",

        -- Overrides for diagnostic commands (nil = default behaviour).
        show_line = nil,   -- override for :LvimLsp diagnostic_current
        goto_next = nil,   -- override for :LvimLsp diagnostic_next
        goto_prev = nil,   -- override for :LvimLsp diagnostic_prev

        -- vim.diagnostic.config() options (nil = not applied).
        virtual_text     = nil,
        virtual_lines    = nil,
        underline        = nil,
        severity_sort    = nil,
        update_in_insert = nil,

        -- Sign symbols per severity.
        signs = nil,
        -- Example:
        -- signs = { error = "", warn = "", hint = "󰌶", info = "" },
    },

    -- INFO POPUP -------------------------------------------------------------

    info = {
        -- Title of the LSP info window.
        popup_title = "LSP SERVERS INFORMATION",
    },

    -- INSTALLER POPUP --------------------------------------------------------

    installer = {
        -- Width of the installer popup.
        -- Fraction 0.1–1.0 (relative to editor width) or absolute integer.
        popup_width = 0.3,

        -- Seconds a completed tool stays visible before disappearing.
        hide_installed_delay = 5,

        -- Title of the installer popup.
        popup_title = "LSP INSTALLER",
    },

    -- POPUP GLOBAL -----------------------------------------------------------

    -- Config passed directly to the lvim-utils UI instance.
    -- Controls border, size, keys, icons, and labels for all popups.
    popup_global = {
        border    = { "", "", "", " ", " ", " ", " ", " " },
        width     = 0.8,
        height    = 0.8,
        max_width = 0.8,
        max_height = 0.8,
        close_keys = { "q", "<Esc>" },
        markview  = false,
        -- ... (full lvim-utils UI configuration)
    },

    -- HIGHLIGHTS -------------------------------------------------------------

    -- Direct nvim_set_hl definitions registered via lvim-utils.highlight.
    -- Survive colorscheme changes automatically.
    -- Defaults link to standard Neovim groups.
    highlights = {
        MasonTitle            = { fg = "#f38ba8", bold = true },
        LvimLspInfoServerName = { fg = "#fab387", bold = true },
        -- ... see full list in the Highlight groups section
    },

    -- DAP --------------------------------------------------------------------

    -- When set, adds the :LvimLsp dap subcommand.
    dap_local_fn = nil,

})
```

---

## Server config module

Each server is described by a Lua module located in one of the `server_config_dirs` directories.

```
my_config/lsp/servers/lua_ls.lua
my_config/lsp/servers/tsserver.lua
```

Module structure:

```lua
-- my_config/lsp/servers/lua_ls.lua
return {

    -- LSP configuration (required)
    lsp = {
        -- Root markers used to determine the project root_dir.
        root_patterns = { ".git", ".luarc.json", ".luarc.jsonc" },

        -- Standard vim.lsp.start configuration.
        config = {
            name = "lua_ls",
            cmd  = { "lua-language-server" },
            settings = {
                Lua = { diagnostics = { globals = { "vim" } } },
            },
            on_attach = function(client, bufnr) end,
        },
    },

    -- EFM tools (optional)
    -- Registers linter/formatter configs for EFM langserver.
    efm = {
        -- Filetypes these tools apply to.
        filetypes = { "lua" },

        -- Tool configs in EFM format (see efm-langserver documentation).
        tools = {
            {
                server_name   = "stylua",
                formatCommand = "stylua --color Never -",
                formatStdin   = true,
            },
        },
    },

    -- DAP configuration (optional)
    -- Automatically registered in nvim-dap on installation.
    dap = {
        adapters = {
            nlua = function(cb, config)
                cb({ type = "server", host = config.host, port = config.port })
            end,
        },
        configurations = {
            lua = {
                {
                    name    = "Attach to running Neovim instance",
                    type    = "nlua",
                    request = "attach",
                    host    = "127.0.0.1",
                    port    = 8086,
                },
            },
        },
    },
}
```

---

## Commands

All commands go through a single entry point: `:LvimLsp <subcommand>`.

### LSP operations

| Subcommand | Description |
|---|---|
| `hover` | Hover information for the symbol under cursor |
| `rename` | Rename symbol |
| `format` | Format the current file |
| `range_format` | Format selected range (Visual mode) |
| `code_action` | Code actions |
| `definition` | Go to definition |
| `type_definition` | Go to type definition |
| `declaration` | Go to declaration |
| `references` | Show all references |
| `implementation` | Go to implementation |
| `signature_help` | Signature help |
| `document_symbol` | Symbols in the current file |
| `workspace_symbol` | Symbols in the workspace |
| `document_highlight` | Highlight all occurrences |
| `clear_references` | Clear highlights |
| `incoming_calls` | Incoming call hierarchy |
| `outgoing_calls` | Outgoing call hierarchy |
| `add_workspace_folder` | Add workspace folder |
| `remove_workspace_folder` | Remove workspace folder |
| `list_workspace_folders` | List workspace folders |

### Diagnostics

| Subcommand | Description |
|---|---|
| `diagnostic_current` | Show diagnostics for the current line |
| `diagnostic_next` | Jump to next diagnostic |
| `diagnostic_prev` | Jump to previous diagnostic |

### Server management

| Subcommand | Description |
|---|---|
| `toggle_servers` | Interactive menu — enable/disable servers globally |
| `toggle_servers_buffer` | Interactive menu — attach/detach servers for the current buffer |
| `restart` | Interactive menu — restart a server |
| `reattach` | Reattach servers to the current buffer |
| `info` | Open LSP info window |

### Project and installations

| Subcommand | Description |
|---|---|
| `project` | Open `.lvim-lsp.lua` for the current project (creates if missing) |
| `declined` | Menu to re-enable declined installations |
| `dap` | DAP command (available only when `dap_local_fn` is set) |

---

## Per-project configuration

`:LvimLsp project` creates `.lvim-lsp.lua` in the project root directory:

```lua
-- .lvim-lsp.lua
return {
    -- Disable specific servers for this project only.
    disable = { "eslint" },

    -- Override global feature flags.
    auto_format = false,
    inlay_hints = true,
    code_lens   = { enabled = true },
}
```

The file is detected automatically on attach. After editing — `:LvimLsp reattach` to apply changes.

---

## Installer

When opening a file, if the dependencies for the corresponding server are missing, a popup appears asking whether to install them via Mason.

- **Space** — toggle a tool
- **Enter** — install selected
- **q / Esc** — skip (server enters a 5-minute cooldown)

Installed tools remain visible for `hide_installed_delay` seconds after completion.

Declined servers are stored in `stdpath("data")/lvim-lsp-declined.json` and can be managed via `:LvimLsp declined`.

---

## LSP Info window

`:LvimLsp info` opens a floating window with detailed information about active clients:

- Encoding, PID, command, root directory
- Workspace folders
- Trigger characters (completion, signature)
- Capabilities tick-list
- Diagnostics (per client and per buffer)
- Attached buffers
- Mason package versions
- EFM: linters and formatters per filetype with diagnostics

---

## CodeLens

When `code_lens.enabled = true`:

- Automatic refresh on `LspAttach`, `TextChanged`, `TextChangedI`
- `:LspCodeLensRun` — execute lens at or near cursor
- `<2-LeftMouse>` (double-click) — execute lens on the line

---

## Lua API

```lua
local lsp = require("lvim-lsp")

-- Install Mason tools and call cb when done.
lsp.ensure_mason_tools({ "lua-language-server", "stylua" }, function() end)

-- Attach/start a server for a buffer.
lsp.ensure_lsp_for_buffer("lua_ls", bufnr)

-- Start a server (force=true → attach to all compatible buffers).
lsp.start_language_server("lua_ls", true)

-- Register EFM tool configs and restart EFM.
lsp.setup_efm({ "lua" }, { { formatCommand = "stylua -", formatStdin = true } })

-- Global disable/enable.
lsp.disable_lsp_server_globally("tsserver")
lsp.enable_lsp_server_globally("tsserver")

-- Per-buffer disable/enable.
lsp.disable_lsp_server_for_buffer("tsserver", bufnr)
lsp.enable_lsp_server_for_buffer("tsserver", bufnr)

-- Compatible servers for a filetype.
lsp.get_compatible_lsp_for_ft("typescript")  -- → { "tsserver", "efm" }

-- Open LSP info window.
lsp.show_info()

-- Debug snapshot of internal state.
lsp.get_state()

-- Debug summary of installer state.
lsp.installer_status()
```

---

## Highlight groups

### Installer progress panel

Configured via `installer.highlights` in setup. All fields are optional — defaults link to standard Neovim groups.

| Field | Default | Description |
|---|---|---|
| `icon_ok` | `"Constant"` | Icon when a tool installs successfully |
| `icon_fail` | `"DiagnosticError"` | Icon when a tool fails |
| `icon_pending` | `"Question"` | Spinner icon during installation |
| `status_ok` | `"Constant"` | Status text when installed |
| `status_fail` | `"DiagnosticError"` | Status text when failed |
| `status_pending` | `"WarningMsg"` | Status text while installing |
| `tool` | `"Title"` | Tool name |
| `action` | `"Comment"` | Current action line (stdout/stderr) |

### LSP info popup
| Group | Description |
|---|---|
| `LvimLspInfoServerName` | Server names |
| `LvimLspInfoSection` | Section headings |
| `LvimLspInfoKey` | Keys (Encoding:, PID: ...) |
| `LvimLspInfoSeparator` | Separator lines |
| `LvimLspInfoLinter` | Linters section |
| `LvimLspInfoFormatter` | Formatters section |
| `LvimLspInfoToolName` | EFM tool names |
| `LvimLspInfoBuffer` | Buffer names |
| `LvimLspIcon` | Icons (■ ◆ ● ✓ ✗) |
