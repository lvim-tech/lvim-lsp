# lvim-lsp

LSP manager for Neovim. Manages the lifecycle of LSP servers, EFM tools, DAP adapters, and Mason installations without third-party config files.

Requires [`lvim-utils`](https://github.com/lvim-tech/lvim-utils) for UI components.

---

## Installation

### lazy.nvim

```lua
{
    "lvim-tech/lvim-lsp",
    dependencies = { "lvim-tech/lvim-utils", "williamboman/mason.nvim" },
    config = function()
        require("lvim-lsp").setup({ ... })
    end,
}
```

### Native (vim.pack / packadd)

```lua
-- In your init.lua, after the plugin is on the runtimepath:
vim.pack.add({
    { src = "https://github.com/lvim-tech/lvim-utils" },
    { src = "https://github.com/williamboman/mason.nvim" },
    { src = "https://github.com/lvim-tech/lvim-lsp" },
})

require("lvim-lsp").setup({ ... })
```

### packer.nvim

```lua
use {
    "lvim-tech/lvim-lsp",
    requires = { "lvim-tech/lvim-utils", "williamboman/mason.nvim" },
    config = function()
        require("lvim-lsp").setup({ ... })
    end,
}
```

Or with `packadd` (plugins cloned under `~/.config/nvim/pack/*/opt/`):

```vim
packadd lvim-utils
packadd mason.nvim
packadd lvim-lsp
```

```lua
require("lvim-lsp").setup({ ... })
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
        -- Title of the LSP info window (icon + text).
        popup_title = "󰨸 LSP SERVERS INFORMATION",

        -- Icons used inside the info window.
        icons = {
            server  = "■",
            section = "◆",
            item    = "●",
            check   = "✓",
            mason   = "󰏗",
            fold    = "➤",
            error   = "󰅙",
            warn    = "󰀨",
            info    = "",
            hint    = "",
        },

        -- Highlight group names for each element.
        -- Override any entry to use your own group.
        highlights = {
            icon       = "LvimLspIcon",
            server     = "LvimLspInfoServerName",
            section    = "LvimLspInfoSection",
            key        = "LvimLspInfoKey",
            value      = "LvimLspInfoValue",
            config_key = "LvimLspInfoConfigKey",
            separator  = "LvimLspInfoSeparator",
            linter     = "LvimLspInfoLinter",
            formatter  = "LvimLspInfoFormatter",
            tool       = "LvimLspInfoToolName",
            buffer     = "LvimLspInfoBuffer",
            fold       = "LvimLspInfoFold",
        },
    },

    -- INSTALLER POPUP --------------------------------------------------------

    installer = {
        -- Ms a completed tool stays visible before disappearing.
        done_ttl = 5000,

        -- Spinner animation frames cycled during active installation.
        spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },

        -- Icons shown per install state.
        icon_ok    = "✓",
        icon_error = "✗",

        -- Appearance of the installer progress panel.
        panel = {
            name      = "LSP Installer",
            icon      = "󰏗",
            header_hl = "LvimNotifyHeaderInfo",
        },

        -- Highlight groups for individual line elements.
        highlights = {
            icon_pending   = "LvimLspInstallerIconPending",
            icon_ok        = "LvimLspInstallerIconOk",
            icon_fail      = "LvimLspInstallerIconFail",
            tool           = "LvimLspInstallerTool",
            status_pending = "LvimLspInstallerStatusPending",
            status_ok      = "LvimLspInstallerStatusOk",
            status_fail    = "LvimLspInstallerStatusFail",
            action         = "LvimLspInstallerAction",
        },
    },

    -- PROGRESS PANEL ---------------------------------------------------------

    progress = {
        -- Enable/disable the LSP progress subsystem.
        enabled = true,

        -- Server names whose progress notifications are suppressed.
        ignore = {},

        -- Ms to keep a completed entry visible.
        done_ttl = 2000,

        -- Icon shown when a token completes.
        done_icon = "✓",

        -- Max concurrent entries shown in the panel.
        render_limit = 4,

        -- Appearance of the progress panel header.
        panel = {
            name      = "LSP Progress",
            icon      = nil,
            header_hl = nil,
        },

        -- Highlight groups for individual progress line elements.
        highlights = {
            icon       = "LvimLspProgressIcon",
            server     = "LvimLspProgressServer",
            title      = "LvimLspProgressTitle",
            done       = "LvimLspProgressDone",
            message    = "LvimLspProgressMessage",
            percentage = "LvimLspProgressPct",
        },
    },

    -- FORM -------------------------------------------------------------------

    form = {
        -- What happens after "Apply permanently" in the project form.
        -- "Close" — close the popup.  "Stay" — remain open.
        after_apply = "Close",
    },

    -- MENUS ------------------------------------------------------------------

    -- Titles and subtitles for interactive management popups.
    menus = {
        toggle_servers = {
            title    = "󱃕 LSP Servers",
            subtitle = "enable / disable / start servers",
        },
        toggle_servers_buffer = {
            title = "󱃕 LSP for Buffer",
            -- subtitle is set dynamically to the current filetype
        },
        restart = {
            title    = "󰑓 Restart LSP",
            subtitle = "select server to restart",
        },
        reattach = {
            title = "󰓦 Reattach LSP",
            -- subtitle is set dynamically to the current filetype
        },
        declined = {
            title    = "󰅙 Declined LSP Tools",
            subtitle = "Space = toggle  ·  Enter = re-enable unchecked  ·  q = cancel",
        },
        -- Install-prompt popup shown when opening a file with missing tools.
        -- title_icon is prepended before "Install LSP tools for <filetype>".
        install = {
            title_icon = "",
            subtitle   = "Space = toggle  ·  Enter = install checked  ·  q = skip",
        },
    },

    -- PROJECT PANEL ----------------------------------------------------------

    project = {
        -- Icon prepended to the panel title.
        title_icon = "󰒓",

        -- Per-tab label and icon for the project settings panel.
        tabs = {
            servers    = { label = "LSP Servers", icon = "󰒋" },
            formatters = { label = "Formatters",  icon = "󰒡" },
            linters    = { label = "Linters",     icon = "󱉶" },
            filetypes  = { label = "Filetypes",   icon = "󰈔" },
            global     = { label = "Global",      icon = "󰒓" },
        },
    },

    -- POPUP GLOBAL -----------------------------------------------------------

    -- Config passed directly to the lvim-utils UI instance used by lvim-lsp.
    -- Overrides apply only to this plugin — other plugins are unaffected.
    -- Controls border, size, keys, icons, labels, and color overrides for
    -- all popups opened by lvim-lsp.
    popup_global = {
        border     = { "", "", "", " ", " ", " ", " ", " " },
        position   = "editor",
        width      = 0.8,
        height     = 0.8,
        max_width  = 0.8,
        max_height = 0.8,
        max_items  = nil,
        close_keys = { "q", "<Esc>" },
        markview   = false,

        -- Icons used in UI elements.
        icons = {
            bool_on        = "󰄬",
            bool_off       = "󰍴",
            select         = "󰘮",
            number         = "󰎠",
            string         = "󰬴",
            action         = "",
            spacer         = "   ──────",
            multi_selected = "󰄬",
            multi_empty    = "󰍴",
            current        = "➤",
        },

        -- Footer labels shown in the key-hint bar.
        labels = {
            navigate = "navigate",
            confirm  = "confirm",
            cancel   = "cancel",
            close    = "close",
            toggle   = "toggle",
            cycle    = "cycle",
            edit     = "edit",
            execute  = "execute",
            tabs     = "tabs",
        },

        -- Key bindings used in all popups.
        keys = {
            down    = "j",
            up      = "k",
            confirm = "<CR>",
            cancel  = "<Esc>",
            close   = "q",
            back    = "u",
            tabs    = { next = "l", prev = "h" },
            select  = { confirm = "<CR>", cancel = "<Esc>" },
            multiselect = { toggle = "<Space>", confirm = "<CR>", cancel = "<Esc>" },
            list    = { next_option = "<Tab>", prev_option = "<BS>" },
        },

        -- Override lvim-utils UI colors for lvim-lsp popups only.
        -- Use standard nvim_set_hl attribute tables.
        -- Example: make popup backgrounds transparent:
        -- highlights = {
        --     LvimUiNormal      = { bg = "NONE" },
        --     LvimUiNormalFloat = { bg = "NONE" },
        -- },
        highlights = {},
    },

    -- NOTIFICATIONS ----------------------------------------------------------

    notify = {
        -- Set to false to silence all plugin notifications globally.
        enabled   = true,
        -- Minimum level to display (vim.log.levels.*).
        min_level = vim.log.levels.INFO,
        -- Title shown in the notification popup.
        title     = "Lvim LSP",
    },

    -- DEBUG LOGGING ----------------------------------------------------------

    debug = {
        -- Set to true to enable file-based debug logging.
        -- Log file: stdpath("state")/lvim-lsp/debug.log
        enabled   = false,
        -- Minimum level to record (vim.log.levels.*).
        min_level = vim.log.levels.DEBUG,
    },

    -- HIGHLIGHTS -------------------------------------------------------------

    -- Override or extend the default LvimLsp* highlight groups.
    -- Registered globally via lvim-utils.highlight — survive colorscheme changes.
    -- Applied on top of the built-in palette-based defaults (always force).
    -- To override lvim-utils UI colors (popup backgrounds, borders, etc.)
    -- use popup_global.highlights instead.
    highlights = {
        -- Example overrides:
        -- LvimLspInfoServerName = { fg = "#fab387", bold = true },
        -- LvimLspProgressIcon   = { fg = "#f38ba8" },
    },

    -- Set to true to always override theme-defined highlight groups.
    -- When false (default), theme-defined groups take priority over the
    -- plugin's palette-based defaults.
    force = false,

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

| Subcommand                | Description                                   |
| ------------------------- | --------------------------------------------- |
| `hover`                   | Hover information for the symbol under cursor |
| `rename`                  | Rename symbol                                 |
| `format`                  | Format the current file                       |
| `range_format`            | Format selected range (Visual mode)           |
| `code_action`             | Code actions                                  |
| `definition`              | Go to definition                              |
| `type_definition`         | Go to type definition                         |
| `declaration`             | Go to declaration                             |
| `references`              | Show all references                           |
| `implementation`          | Go to implementation                          |
| `signature_help`          | Signature help                                |
| `document_symbol`         | Symbols in the current file                   |
| `workspace_symbol`        | Symbols in the workspace                      |
| `document_highlight`      | Highlight all occurrences                     |
| `clear_references`        | Clear highlights                              |
| `incoming_calls`          | Incoming call hierarchy                       |
| `outgoing_calls`          | Outgoing call hierarchy                       |
| `add_workspace_folder`    | Add workspace folder                          |
| `remove_workspace_folder` | Remove workspace folder                       |
| `list_workspace_folders`  | List workspace folders                        |

### Diagnostics

| Subcommand           | Description                           |
| -------------------- | ------------------------------------- |
| `diagnostic_current` | Show diagnostics for the current line |
| `diagnostic_next`    | Jump to next diagnostic               |
| `diagnostic_prev`    | Jump to previous diagnostic           |

### Server management

| Subcommand              | Description                                                     |
| ----------------------- | --------------------------------------------------------------- |
| `toggle_servers`        | Interactive menu — enable/disable servers globally              |
| `toggle_servers_buffer` | Interactive menu — attach/detach servers for the current buffer |
| `restart`               | Interactive menu — restart running servers                      |
| `reattach`              | Interactive menu — reattach servers to the current buffer       |
| `info`                  | Open LSP info window                                            |

### Project and installations

| Subcommand | Description                                                          |
| ---------- | -------------------------------------------------------------------- |
| `project`  | Open per-project settings panel (creates `.lvim-lsp.lua` if missing) |
| `declined` | Interactive menu — re-enable previously declined tool installations  |
| `dap`      | DAP command (available only when `dap_local_fn` is set)              |

---

## Per-project configuration

`:LvimLsp project` opens a tabbed settings panel for the current project root. Changes are saved to `.lvim-lsp.lua` in the project root directory.

The file can also be edited manually:

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

The file is detected automatically on attach. After editing manually — `:LvimLsp reattach` to apply changes immediately.

---

## Installer

When opening a file, if the dependencies for the corresponding server are missing, a popup appears asking whether to install them via Mason.

- **Space** — toggle a tool on/off
- **Enter** — install all checked tools
- **q / Esc** — skip (re-prompting is suppressed for 5 minutes)

Unchecked tools are recorded as declined and skipped on future file opens.

Declined tools are stored in `stdpath("data")/lvim-lsp-declined.json` and can be reviewed and re-enabled via `:LvimLsp declined`.

Installed tools remain visible in the progress panel for `installer.done_ttl` ms after completion.

---

## LSP Info window

`:LvimLsp info` opens a floating window with detailed information about active clients:

- Encoding, PID, command, root directory
- Workspace folders
- Trigger characters (completion, signature)
- Capabilities tick-list (with foldable Server Capabilities / Settings sections)
- Diagnostics per client and per buffer
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

## Debug logging

When `debug.enabled = true`, all internal events are written to:

```
stdpath("state")/lvim-lsp/debug.log
```

Format: `YYYY-MM-DD HH:MM:SS [LEVEL] message`

Control the minimum recorded level with `debug.min_level` (`vim.log.levels.DEBUG` by default).

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

-- Progress control.
lsp.suppress_progress(true)
lsp.clear_progress()
lsp.get_progress_status()  -- → compact string for statusline
```

---

## Highlight groups

### Named groups (`highlights`)

Registered globally via `lvim-utils.highlight` — survive colorscheme changes.
Built from the shared `lvim-utils.colors` palette. Override via the `highlights` key in setup.
Set `force = true` to always override theme-defined groups (default: theme wins).

#### Info window

| Group                   | Default color | Description                               |
| ----------------------- | ------------- | ----------------------------------------- |
| `LvimLspIcon`           | blue          | General icons (■ ◆ ●)                     |
| `LvimLspInfoServerName` | orange        | Server names                              |
| `LvimLspInfoSection`    | blue          | Section headings                          |
| `LvimLspInfoKey`        | yellow        | Keys (Encoding:, PID: …)                  |
| `LvimLspInfoValue`      | fg            | Values next to keys                       |
| `LvimLspInfoConfigKey`  | teal          | Keys inside Settings / Capabilities folds |
| `LvimLspInfoSeparator`  | blue×50%      | Separator lines                           |
| `LvimLspInfoLinter`     | cyan          | Linter entries                            |
| `LvimLspInfoFormatter`  | cyan          | Formatter entries                         |
| `LvimLspInfoToolName`   | yellow        | EFM tool names                            |
| `LvimLspInfoBuffer`     | teal          | Buffer names                              |
| `LvimLspInfoFold`       | purple        | Fold indicator icon (➤)                   |

#### Installer panel

| Group                           | Default color | Description                            |
| ------------------------------- | ------------- | -------------------------------------- |
| `LvimLspInstallerIconPending`   | yellow        | Spinner icon during installation       |
| `LvimLspInstallerIconOk`        | green         | Icon when a tool installs successfully |
| `LvimLspInstallerIconFail`      | red           | Icon when a tool fails                 |
| `LvimLspInstallerTool`          | purple bold   | Tool name                              |
| `LvimLspInstallerStatusPending` | yellow        | Status text while installing           |
| `LvimLspInstallerStatusOk`      | green         | Status text when installed             |
| `LvimLspInstallerStatusFail`    | red           | Status text when failed                |
| `LvimLspInstallerAction`        | teal          | Current action line (stdout/stderr)    |

#### Progress panel

| Group                    | Default color | Description         |
| ------------------------ | ------------- | ------------------- |
| `LvimLspProgressIcon`    | yellow        | Spinner / done icon |
| `LvimLspProgressServer`  | purple bold   | Server name         |
| `LvimLspProgressTitle`   | yellow        | In-progress title   |
| `LvimLspProgressDone`    | green         | Completed title     |
| `LvimLspProgressMessage` | teal          | Message text        |
| `LvimLspProgressPct`     | magenta       | Percentage value    |

---

### Info window element overrides (`info.highlights`)

Each element of the info window resolves its highlight group through `info.highlights`.
Override individual entries to remap an element to any existing group:

```lua
info = {
    highlights = {
        icon       = "LvimLspIcon",           -- general icons
        server     = "LvimLspInfoServerName", -- server name line
        section    = "LvimLspInfoSection",    -- section headings
        key        = "LvimLspInfoKey",        -- key: value pairs
        value      = "LvimLspInfoValue",      -- values in key: value pairs
        config_key = "LvimLspInfoConfigKey",  -- keys inside foldable sections
        separator  = "LvimLspInfoSeparator",  -- separator lines
        linter     = "LvimLspInfoLinter",     -- linter entries
        formatter  = "LvimLspInfoFormatter",  -- formatter entries
        tool       = "LvimLspInfoToolName",   -- EFM tool names
        buffer     = "LvimLspInfoBuffer",     -- buffer names
        fold       = "LvimLspInfoFold",       -- fold indicator icon
    },
},
```

---

### Popup color overrides (`popup_global.highlights`)

`popup_global.highlights` overrides lvim-utils UI colors **only for lvim-lsp popups**.
Other plugins using lvim-utils are unaffected.

```lua
popup_global = {
    highlights = {
        LvimUiNormal      = { bg = "NONE" },
        LvimUiNormalFloat = { bg = "NONE" },
        LvimUiBorder      = { fg = "#89b4fa" },
        -- any LvimUi* group accepted here
    },
},
```

> **Note** — `highlights` (top-level) registers global named groups via `hl.register()`.
> `popup_global.highlights` creates anonymous inline overrides scoped to this instance.
> Use the former for `LvimLsp*` groups and the latter for `LvimUi*` groups.
