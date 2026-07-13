# lvim-lsp

The **UI layer** of the LVIM LSP stack. It drives the
[`lvim-ls`](https://github.com/lvim-tech/lvim-ls) engine (LSP lifecycle, EFM
tools, DAP requirements, project resolution) and renders its panels, forms, info
windows and notifications. Tool installation is delegated to
[`lvim-pkg`](https://github.com/lvim-tech/lvim-pkg) /
[`lvim-installer`](https://github.com/lvim-tech/lvim-installer) — no third-party
config files.

Requires [`lvim-ls`](https://github.com/lvim-tech/lvim-ls) (engine) and
[`lvim-utils`](https://github.com/lvim-tech/lvim-utils) (UI).

---

[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](https://github.com/lvim-tech/lvim-lsp/blob/main/LICENSE)

## Installation

Requires Neovim >= 0.10, [`lvim-ls`](https://github.com/lvim-tech/lvim-ls) (engine) and
[`lvim-utils`](https://github.com/lvim-tech/lvim-utils) (UI).

### lvim-installer (recommended)

Install and manage it from the LVIM package manager — open the **Plugins** tab and install / update / pin it:

```vim
:LvimInstaller plugins
```

lvim-installer installs plugins through Neovim's built-in `vim.pack`, so no external plugin manager is needed.

### Native (vim.pack)

```lua
vim.pack.add({
    { src = "https://github.com/lvim-tech/lvim-ls" },
    { src = "https://github.com/lvim-tech/lvim-utils" },
    { src = "https://github.com/lvim-tech/lvim-lsp" },
})
require("lvim-lsp").setup({})
```

---

## Quick start

```lua
require("lvim-lsp").setup({
    file_types = {
        lua_ls = {
            filetypes = { "lua" },
            lsp = { "lua-language-server" },
            formatters = { "stylua" },
        },
        tsserver = {
            filetypes = { "typescript", "javascript", "typescriptreact" },
            lsp = { "typescript-language-server" },
        },
        rust_analyzer = {
            filetypes = { "rust" },
            lsp = { "rust-analyzer" },
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
            filetypes = { "lua" },
            lsp = { "lua-language-server" },
            formatters = { "stylua" },
        },
        tsserver = {
            filetypes = { "typescript", "javascript" },
            lsp = { "typescript-language-server" },
        },
        go = {
            filetypes = { "go", "gomod" },
            lsp = { "gopls" },
            debuggers = { { "delve", bin = "dlv" } },
        },
    },

    -- Lua require prefixes searched in order for server config modules.
    -- First match wins.
    server_config_dirs = { "my_config.lsp.servers" },

    -- CALLBACKS --------------------------------------------------------------

    -- Called for every LSP client after attach.
    on_attach = function(client, bufnr) end,

    -- Called after DirChanged (after old-project servers are stopped).
    -- Useful for clearing progress panels or similar.
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

        -- Replace the built-in `:LvimLsp diagnostic_current/next/prev` with your own functions
        -- (nil = use the plugin's themed interactive float — see the "Diagnostics" section below).
        show_line = nil, -- override for :LvimLsp diagnostic_current
        goto_next = nil, -- override for :LvimLsp diagnostic_next
        goto_prev = nil, -- override for :LvimLsp diagnostic_prev

        -- The ➤ selection marker drawn on the active row of the interactive float.
        marker = {
            enabled = true, -- false hides the marker entirely
            icon = "➤", -- the pointer glyph
            pad = { 1, 1 }, -- spaces { before, after } the icon → " ➤ "
            hl = nil, -- nil = derive per row (fg = severity colour, bg = a tint of it);
            -- a string = a fixed group; a function(base_hl) = a programmable group
            bg_tint = 0.3, -- the derived bg tint of the fg (0 = no bg)
        },
        -- Spaces { before, after } each message line, independent of the marker.
        text_pad = { 1, 1 },
        -- Max float width: a fraction of the screen (<= 1) or absolute columns. The float HUGS the
        -- content and only grows up to this cap; it never pads wider than the content.
        max_width = 0.8,

        -- vim.diagnostic.config() options (nil = not applied).
        virtual_text = nil,
        virtual_lines = nil,
        underline = nil,
        severity_sort = nil,
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

        -- Icons used inside the info window (client → section → item tree).
        icons = {
            server = "󰝤",
            section = "󰜁",
            item = "󰝥",
            check = "󰄬",
            mason = "󰏗",
            fold = "➤",
            -- Diagnostic severity glyphs — FALLBACK ONLY: your Neovim signs
            -- (vim.diagnostic.config().signs.text) are honoured first.
            error = "",
            warn = "",
            info = "",
            hint = "󰌵",
        },

        -- Highlight group names for each element.
        -- Override any entry to use your own group.
        highlights = {
            icon = "LvimLspIcon",
            server = "LvimLspInfoServerName",
            section = "LvimLspInfoSection",
            key = "LvimLspInfoKey",
            value = "LvimLspInfoValue",
            config_key = "LvimLspInfoConfigKey",
            separator = "LvimLspInfoSeparator",
            linter = "LvimLspInfoLinter",
            formatter = "LvimLspInfoFormatter",
            tool = "LvimLspInfoToolName",
            buffer = "LvimLspInfoBuffer",
            fold = "LvimLspInfoFold",
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

        -- Spinner frames cycled while work is in progress (Nerd Font pie fill).
        spinner = { "󰪞", "󰪟", "󰪠", "󰪡", "󰪢", "󰪣", "󰪤", "󰪥" },

        -- Icon shown when a token completes.
        done_icon = "󰄬",

        -- Max concurrent entries shown in the panel.
        render_limit = 4,

        -- Appearance of the progress panel header.
        panel = {
            name = "LSP Progress",
            icon = nil,
            header_hl = nil,
        },

        -- Highlight groups for individual progress line elements.
        highlights = {
            icon = "LvimLspProgressIcon",
            server = "LvimLspProgressServer",
            title = "LvimLspProgressTitle",
            done = "LvimLspProgressDone",
            message = "LvimLspProgressMessage",
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
            title = "󱃕 LSP Servers",
            subtitle = "enable / disable / start servers",
        },
        toggle_servers_buffer = {
            title = "󱃕 LSP for Buffer",
            -- subtitle is set dynamically to the current filetype
        },
        restart = {
            title = "󰑓 Restart LSP",
            subtitle = "select server to restart",
        },
        reattach = {
            title = "󰓦 Reattach LSP",
            -- subtitle is set dynamically to the current filetype
        },
        declined = {
            title = "󰅙 Declined Packages",
            subtitle = "uncheck to re-enable for its filetype",
        },
    },

    -- PROJECT PANEL ----------------------------------------------------------

    project = {
        -- Icon prepended to the panel title.
        title_icon = "󰒓",

        -- Per-tab label and icon for the project settings panel.
        tabs = {
            servers = { label = "LSP Servers", icon = "󰒋" },
            formatters = { label = "Formatters", icon = "󰒡" },
            linters = { label = "Linters", icon = "󱉶" },
            filetypes = { label = "Filetypes", icon = "󰈔" },
            global = { label = "Global", icon = "󰒓" },
        },
    },

    -- POPUP GLOBAL -----------------------------------------------------------

    -- Config passed directly to the lvim-utils UI instance used by lvim-lsp.
    -- Overrides apply only to this plugin — other plugins are unaffected.
    -- Controls size, keys, icons, labels, and color overrides for all popups
    -- opened by lvim-lsp. (The frame BORDER is no longer set here — every panel
    -- now follows the single shared lvim-utils `config.ui.border`.)
    popup_global = {
        position = "editor",
        width = 0.8,
        height = 0.8,
        max_width = 0.8,
        max_height = 0.8,
        max_items = nil,
        close_keys = { "q", "<Esc>" },
        markview = false,

        -- Icons used in UI elements.
        icons = {
            bool_on = "󰄬",
            bool_off = "󰍴",
            select = "󰘮",
            number = "󰎠",
            string = "󰬴",
            action = "",
            spacer = "   ──────",
            multi_selected = "󰄬",
            multi_empty = "󰍴",
            current = "➤",
        },

        -- Footer labels shown in the key-hint bar.
        labels = {
            navigate = "navigate",
            confirm = "confirm",
            cancel = "cancel",
            close = "close",
            toggle = "toggle",
            cycle = "cycle",
            edit = "edit",
            execute = "execute",
            tabs = "tabs",
        },

        -- Key bindings used in all popups.
        keys = {
            down = "j",
            up = "k",
            confirm = "<CR>",
            cancel = "<Esc>",
            close = "q",
            back = "u",
            tabs = { next = "l", prev = "h" },
            select = { confirm = "<CR>", cancel = "<Esc>" },
            multiselect = { toggle = "<Space>", confirm = "<CR>", cancel = "<Esc>" },
            list = { next_option = "<Tab>", prev_option = "<BS>" },
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
        enabled = true,
        -- Minimum level to display (vim.log.levels.*).
        min_level = vim.log.levels.INFO,
        -- Title shown in the notification popup.
        title = "Lvim LSP",
    },

    -- DEBUG LOGGING ----------------------------------------------------------

    debug = {
        -- Set to true to enable file-based debug logging.
        -- Log file: stdpath("state")/lvim-lsp/debug.log
        enabled = false,
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

    -- LOCATION PEEK ----------------------------------------------------------

    -- How every "go to / list locations" command (definition, references, diagnostics, call
    -- hierarchy, symbols, …) is presented. TWO global knobs, overridable PER CALL through the
    -- public API (e.g. `require("lvim-lsp").definition({ layout = "float" })`) or a command arg
    -- (`:LvimLsp definition native`):
    --   native = false → OUR system (the lvim-utils picker / peek) — the DEFAULT, modern layout
    --   native = true  → Neovim's built-in handlers (quickfix / direct jump) everywhere
    --   layout         → which picker layout: "area" (msgarea zone, DEFAULT) | "float" | "bottom"
    -- A single location result always jumps directly, regardless.
    peek = {
        native = false,
        layout = "area",

        -- true = the peek joins the shared dock STACK (cyclable <Leader>n/p/x/m, :LvimDock,
        -- one-visible-per-layout, no overlap); false = geometry-only standalone open (still
        -- centrally sized/backdropped, NOT in the stack). Forwarded to lvim-picker.
        dock_stack = true,

        -- Per-layout ANCHORED geometry overrides, deep-merged per field OVER the global
        -- lvim-utils dock geometry; empty {} = inherit unchanged. Each layout may carry:
        -- height, height_auto, backdrop = { enabled, mode, dim = { amount }, darken = { amount } },
        -- auto_hide, keep_focus. float ALSO: width, width_auto. area/bottom are always full-width.
        force = { float = {}, area = {}, bottom = {} },

        -- Appearance, forwarded to the lvim-utils picker / peek.
        appearance = {
            list_wrap = true, -- soft-wrap long list rows (false = truncate)
            expand = "manual", -- "auto" = only the focused group open (follows cursor); "manual" = toggle
            list_position = "left",
            list_width = 0.4, -- 40% list / 60% preview (drag the divider to adjust live)
            preview_height = 16,
            icon = "󰈭", -- glyph fronting the peek title + its single dock-stack entry
        },
    },

    -- OUTLINE ----------------------------------------------------------------

    -- Document Symbols outline (:LvimLsp outline) — a persistent side-split panel that lists the
    -- current file's symbol tree and follows the cursor.
    outline = {
        position = "right", -- "right" | "left" — which side the panel docks on
        width = 0.25, -- fraction of the editor width (or absolute columns if > 1)
        title = "LVIM LSP OUTLINE", -- full-width winbar label; false/"" hides it

        follow = true, -- highlight the symbol under the source cursor as you move
        auto_fold = true, -- accordion: keep only the current symbol's ancestors open
        auto_close = false, -- close the panel after jumping to a symbol
        fold_initial = "none", -- "none" (all expanded) | "all" (all collapsed)
        detail = true, -- show each symbol's detail/signature as dim virtual text
        source_colors = true, -- colour names/icons from the buffer's own highlights

        -- Panel keymaps (each may be a string or a list of strings). Press `g?` inside for the cheatsheet.
        keys = {
            goto_location = "<CR>", -- jump to the symbol (honours auto_close)
            goto_and_close = "<S-CR>", -- jump and close the panel
            peek_location = "o", -- move the source cursor to the symbol but stay in the panel
            restore_location = "<C-g>", -- restore the source cursor to where peeking began
            up_and_jump = "<C-k>", -- previous symbol + peek
            down_and_jump = "<C-j>", -- next symbol + peek
            fold = "h", -- collapse the symbol under the cursor
            unfold = "l", -- expand it
            fold_toggle = "<Tab>", -- toggle it
            fold_all = "W", -- collapse every symbol
            unfold_all = "E", -- expand every symbol
            fold_toggle_all = "<S-Tab>", -- toggle all
            fold_reset = "R", -- reset folds to fold_initial
            fold_auto = "A", -- (re)enable the accordion auto-fold
            hover_symbol = "<C-space>", -- LSP hover on the symbol
            code_actions = "a", -- code actions at the symbol
            rename_symbol = "r", -- rename the symbol
            help = "g?", -- show the cheatsheet
            close = { "q", "<Esc>" }, -- close the panel
        },
        -- Tree chrome glyphs (all configurable).
        fold = { open = "", closed = "" },
        guide = "│", -- vertical continuation line
        branch = "├", -- a leaf with siblings below it
        branch_last = "└", -- the last leaf in its group
        -- SymbolKind → glyph (keyed by the LSP SymbolKind name). See config/ui.lua for the full set.
        icons = { Function = "󰊕", Class = "󰠱", Method = "󰆧", Variable = "󰀫" }, -- (partial)
    },

    -- HOVER ------------------------------------------------------------------

    -- When enabled, :LvimLsp hover renders the documentation in a themed float (house chrome,
    -- markdown-rendered) instead of Neovim's built-in popup. Opens unfocused; press again to focus.
    hover = {
        enabled = false,
        title = " Hover",
        wrap = true,
    },

    -- LIGHTBULB --------------------------------------------------------------

    -- Code-action availability indicator: when the cursor rests on a line where an attached
    -- client offers code actions, a 󰌵 hint appears — EOL virtual text (a soft yellow chip)
    -- or a sign-column glyph. Debounced on CursorHold/CursorMoved; the in-flight request is
    -- cancelled before the next fires. Per-buffer opt-out: vim.b.lvim_lsp_lightbulb_disable.
    lightbulb = {
        enabled = true,
        placement = "virtual_text", -- "virtual_text" (EOL chip) | "sign" (sign column)
        icon = "󰌵",
        update_ms = 150, -- debounce (ms) between the last cursor event and the probe
        only = nil, -- CodeActionKind filter (context.only) — nil = all kinds,
        -- or e.g. { "quickfix", "refactor" } so source/format actions don't light it constantly
        show_preferred = true, -- raise the accent yellow → orange when an action isPreferred
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
            cmd = { "lua-language-server" },
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
                server_name = "stylua",
                formatCommand = "stylua --color Never -",
                formatStdin = true,
            },
        },
    },

    -- DAP configuration (optional)
    -- Automatically registered with the DAP client on installation.
    dap = {
        adapters = {
            nlua = function(cb, config)
                cb({ type = "server", host = config.host, port = config.port })
            end,
        },
        configurations = {
            lua = {
                {
                    name = "Attach to running Neovim instance",
                    type = "nlua",
                    request = "attach",
                    host = "127.0.0.1",
                    port = 8086,
                },
            },
        },
    },
}
```

---

## Commands

All commands go through a single entry point: `:LvimLsp <subcommand>`.

The navigation subcommands (see the table) accept an optional layout arg:
`:LvimLsp <feature> [native|area|float|bottom]` — overriding the global `peek` knobs for that one call
(`native` = Neovim's built-in handler; `area`/`float`/`bottom` = the lvim-utils picker layout).

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
| `outline`                 | Toggle the Document Symbols outline panel     |
| `outline_focus`           | Open (if needed) and focus the outline panel  |
| `document_highlight`      | Highlight all occurrences                     |
| `clear_references`        | Clear highlights                              |
| `incoming_calls`          | Incoming call hierarchy                       |
| `outgoing_calls`          | Outgoing call hierarchy                       |
| `add_workspace_folder`    | Add workspace folder                          |
| `remove_workspace_folder` | Remove workspace folder                       |
| `list_workspace_folders`  | List workspace folders                        |

### Feature toggles

| Subcommand           | Description                                        |
| -------------------- | -------------------------------------------------- |
| `toggle_inlay_hints` | Toggle inlay hints for the current buffer (0.10+)  |
| `toggle_codelens`    | Toggle CodeLens for the current buffer             |

### Diagnostics

| Subcommand           | Description                                                          |
| -------------------- | ------------------------------------------------------------------- |
| `diagnostic_current` | Open the interactive float for the current line (most severe first) |
| `diagnostic_next`    | Walk to the next diagnostic and show it in the float                |
| `diagnostic_prev`    | Walk to the previous diagnostic and show it in the float            |
| `diagnostics`        | Two-pane diagnostics navigator with a filter bar                    |

### Server management

| Subcommand              | Description                                                     |
| ----------------------- | --------------------------------------------------------------- |
| `toggle_servers`        | Interactive menu — enable/disable servers globally              |
| `toggle_servers_buffer` | Interactive menu — attach/detach servers for the current buffer |
| `restart`               | Interactive menu — restart running servers                      |
| `reattach`              | Interactive menu — reattach servers to the current buffer       |
| `info`                  | Open LSP info window                                            |
| `log`                   | Open the debug log in a read-only split (`debug.enabled`)       |

### Project and installations

| Subcommand | Description                                                          |
| ---------- | -------------------------------------------------------------------- |
| `project`  | Open per-project settings panel (creates `.lvim-lsp.lua` if missing) |
| `declined` | Interactive menu — re-enable previously declined tool installations  |
| `dap`      | DAP command (available only when `dap_local_fn` is set)              |

---

## Location peek

The navigation commands — `definition`, `type_definition`, `declaration`, `references`,
`implementation`, `incoming_calls`, `outgoing_calls`, `workspace_symbol`, `document_symbol`,
`diagnostics` — render their results through the **lvim-utils picker / peek**: a location list grouped
by file on one side, a live preview of the focused location on the other. It is controlled by **two
global knobs** under `peek`:

```lua
peek = {
    native = false, -- false = the lvim-utils picker/peek (default); true = Neovim's built-in handlers
    layout = "area", -- "area" (msgarea zone, default) | "float" | "bottom"
    dock_stack = true, -- true = managed dock-stack entry; false = geometry-only standalone open
    force = { float = {}, area = {}, bottom = {} }, -- per-layout anchored geometry overrides
    appearance = { ... }, -- forwarded to the lvim-utils picker/peek (see the config block above)
}
```

Both are overridable **per call** — through the public API
(`require("lvim-lsp").definition({ layout = "float" })`) or a command arg
(`:LvimLsp definition native`). A single location result always jumps directly, regardless.

In the peek list: `j`/`k` move, `<CR>` open, `<C-x>` open in a split, `<C-v>` in a vsplit, `q` close.
(The list has a live query input, so the jump keys are chords — plain letters go into the filter.)

When `dock_stack = true` (default), the location/diagnostics peek joins the shared **dock stack** as a
single entry (glyph from `appearance.icon`), so it is one visible per layout — it never overlaps a docked
picker or terminal — and is cyclable with `<Leader>n`/`<Leader>p`, closable with `<Leader>x`, and listed
in `<Leader>m`. Its name in that menu follows the current peek's title (References / Definitions /
Diagnostics …). Set `dock_stack = false` to open the peek standalone (still centrally sized/backdropped,
just outside the stack). `force` overrides the peek's geometry per layout — e.g. `force.area = { height =
0.3 }` shrinks the area peek, `force.float = { width = 0.5, height = 0.6 }` resizes the float; area/bottom
are always full-width, so their `width` is ignored.

### Diagnostics navigator

`:LvimLsp diagnostics` opens the same picker over **diagnostics**: every diagnostic grouped by file
(each row carrying its severity sign) on the left, a live preview on the right. Centred under the
title, a **filter bar** carries two button groups with bracketed hotkeys — a scope toggle
(`[W]orkspace` = whole workspace / `[B]uffer` = the file focused when opened) and a severity filter
(`[A]ll [E]rror [W]arn [I]nfo [H]int`). Press a button's letter (scope uses `Shift+W` / `b`; severity
`a e w i h`), click it, or press `f` to cycle severity — all re-filter the list live, each button
showing its current count. `:LvimLsp diagnostics native` falls back to `vim.diagnostic.setqflist()`.

---

## Document Symbols outline

`:LvimLsp outline` toggles a persistent side-split **outline panel** that lists the current file's
symbol tree and follows the cursor as you move in the source; `:LvimLsp outline_focus` opens it (if
needed) and moves focus into it. It is a real split window (native `<C-w>` navigation), docked on the
`outline.position` side at `outline.width` of the editor.

- **Follow + accordion** — with `follow = true` the symbol under the source cursor is highlighted;
  with `auto_fold = true` only that symbol's ancestors stay open (any manual fold suspends it; `A`
  resumes it).
- **Jump / peek** — `<CR>` jumps to the symbol (honouring `auto_close`), `o` moves the source cursor
  but keeps focus in the panel, `<C-j>`/`<C-k>` walk + peek, `<C-g>` restores the pre-peek position.
- **Folds** — `h`/`l`/`<Tab>` fold/unfold/toggle the symbol, `W`/`E`/`<S-Tab>` do it for all, `R`
  resets to `fold_initial`.
- **LSP at the symbol** — `<C-space>` hover, `a` code actions, `r` rename.
- **Colours** — with `source_colors = true` names and icons take the symbol's own colour from the
  buffer (treesitter / semantic tokens), else the per-kind palette colours.

All keys are configurable under `outline.keys`; press `g?` in the panel for the live cheatsheet.

---

## Hover

With `hover.enabled = true`, `:LvimLsp hover` renders the documentation in a themed float (the
house chrome shared with the rest of lvim-lsp's UI, with markdown rendering) instead of Neovim's
built-in popup. The float opens unfocused; press the trigger key again to focus and scroll it.

```lua
hover = { enabled = true, title = " Hover" }
```

---

## Code-action lightbulb

With `lightbulb.enabled = true` (the default), a `󰌵` hint appears on the cursor line whenever an
attached LSP client offers a **code action** there — so actions are discoverable without probing
`:LvimLsp code_action` blindly:

- **Placement** — `placement = "virtual_text"` (default) renders it as a soft yellow chip
  immediately after the line's text; `placement = "sign"` puts the glyph in the sign column.
- **Preferred accent** — with `show_preferred = true`, the accent raises yellow → orange when any
  offered action is marked `isPreferred` by the server.
- **Timing** — updates are debounced (`update_ms`) on `CursorHold`/`CursorMoved` in normal mode; the
  previous in-flight request is cancelled before the next is issued, and a late response for an
  older cursor position is dropped. The hint clears on `InsertEnter`, on leaving the buffer, when
  the result is empty, and when the last codeAction-capable client detaches.
- **Kind filter** — `only = { "quickfix", "refactor" }` narrows the probe to those
  `CodeActionKind`s (forwarded as `context.only`), so ubiquitous source/format actions don't light
  the bulb constantly. `nil` (default) = all kinds.
- **Per-buffer opt-out** — set `vim.b.lvim_lsp_lightbulb_disable = true` in a buffer (e.g. large
  generated files) to keep it dark there.

For statusline / winbar consumers, `require("lvim-lsp").get_lightbulb(bufnr)` returns
`{ count, preferred }` — the availability at the last completed probe.

---

## Diagnostics

`:LvimLsp diagnostic_current` (and `diagnostic_next` / `diagnostic_prev`) open an **interactive
float** for the diagnostics on a line — the same house chrome as the hover:

- Each diagnostic shows as `message  (source)`, the message in its severity colour, the source
  dimmed, sorted with the most severe first; the count is in the title.
- A `➤` marks the selected diagnostic. `diagnostic_current` lands on the **most severe** one;
  `next` / `diagnostic_prev` **walk every individual diagnostic** in document order (line →
  severity → column), so arriving at a line lands on its error and several at one position are
  each visited (told apart by their message).
- Press the trigger key (`<CR>` by default) to focus the float, then `j`/`k` or `n`/`p` to move
  the selection — the editor cursor follows. `q` closes it; a manual cursor move dismisses it.
- The one float window is **reused** as you navigate (re-rendered and repositioned in place, never
  closed and reopened), so there is no flicker.

Tune the `➤` marker, the message padding and the max float width via `diagnostics.marker`,
`diagnostics.text_pad` and `diagnostics.max_width` — the float hugs the content and only grows up to that
cap (see the configuration block above).

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
    code_lens = { enabled = true },
}
```

The file is detected automatically on attach. After editing manually — `:LvimLsp reattach` to apply changes immediately.

---

## Installer

When you open a file whose server needs tools that are not installed, lvim-installer's
unified prompt offers them in a tabbed checklist (grouped by LSP / DAP / Linter /
Formatter / Treesitter). Footer buttons, fired by their key:

- **a** — install all
- **s** — install only the checked
- **c** — cancel (install nothing)
- **q / Esc** — quick skip (re-prompting is snoozed for 5 minutes)

When packages are skipped (Cancel, or Install-selected with some unchecked) a second
prompt offers to **decline** them for that filetype — persisted in `lvim-pkg`'s
database and filtered out of every future prompt — or to snooze. Review and re-enable
declines via `:LvimLsp declined`.

Installation progress is rendered by lvim-installer itself (lvim-lsp only triggers the prompt).

---

## LSP Info window

`:LvimLsp info` opens a floating window with detailed information about active clients (EFM first):

- Encoding, PID, command, root directory
- Workspace folders
- Capabilities tick-list
- Diagnostics per client and per buffer
- Attached buffers
- Mason package versions
- EFM: linters and formatters per filetype with diagnostics
- Full Server Capabilities and Settings (nested, collapsible)

Every section is a fold, **collapsed by default** — a closed section reads as its header (in its own
colours) plus a hidden-line count. `<CR>` toggles the section under the cursor; the footer carries `zM`
collapse all, `zR` expand all, and `q` close. The hardware cursor is hidden (the active row reads via the
cursorline).

---

## CodeLens

When `code_lens.enabled = true`:

- Automatic refresh on `LspAttach`, `TextChanged`, `TextChangedI`
- `:LspCodeLensRun` — execute lens at or near cursor
- `<2-LeftMouse>` (double-click) — execute lens on the line

---

## Debug logging

When `debug.enabled = true`, all internal events are written by the lvim-ls engine to:

```
stdpath("state")/lvim-ls/debug.log
```

Format: `YYYY-MM-DD HH:MM:SS [LEVEL] message`

Control the minimum recorded level with `debug.min_level` (`vim.log.levels.DEBUG` by default).
Open the log in a read-only split with `:LvimLsp log`.

---

## Lua API

```lua
local lsp = require("lvim-lsp")

-- Navigation (keymap-friendly). Each takes an optional { native?, layout? } that overrides the
-- global `peek` knobs for that call; falls back to config.peek.native / config.peek.layout.
--   layout = "area" (default) | "float" | "bottom";  native = true → Neovim's built-in handler.
lsp.definition() -- e.g. lsp.definition({ layout = "float" })
lsp.type_definition()
lsp.declaration()
lsp.references()
lsp.implementation()
lsp.incoming_calls()
lsp.outgoing_calls()
lsp.workspace_symbol()
lsp.document_symbol()
lsp.diagnostics() -- the two-pane diagnostics navigator
lsp.hover()
lsp.outline() -- toggle the Document Symbols outline panel

-- Missing tools for a filetype, grouped by the server that needs them
-- (pure data — performs no installation).
lsp.missing_for_ft("lua")

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
lsp.get_compatible_lsp_for_ft("typescript") -- → { "tsserver", "efm" }

-- Open LSP info window.
lsp.show_info()

-- Debug snapshot of internal state.
lsp.get_state()

-- Progress control.
lsp.suppress_progress(true)
lsp.clear_progress()
lsp.get_progress_status() -- → compact string for statusline

-- Attached servers + diagnostic counts for a buffer (statusline).
lsp.get_attached_status(bufnr) -- → "lua_ls, efm  E1 W2"  ("" when none)

-- Code-action availability at the last lightbulb probe (statusline/winbar).
lsp.get_lightbulb(bufnr) -- → { count = 2, preferred = true }  ({ count = 0 } when none)
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
| `LvimLspIcon`           | blue          | General icons (server / section / item)   |
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

#### Progress panel

| Group                    | Default color | Description         |
| ------------------------ | ------------- | ------------------- |
| `LvimLspProgressIcon`    | yellow        | Spinner / done icon |
| `LvimLspProgressServer`  | purple bold   | Server name         |
| `LvimLspProgressTitle`   | yellow        | In-progress title   |
| `LvimLspProgressDone`    | green         | Completed title     |
| `LvimLspProgressMessage` | teal          | Message text        |
| `LvimLspProgressPct`     | magenta       | Percentage value    |

#### Document Symbols outline panel

| Group                     | Default color   | Description                                    |
| ------------------------- | --------------- | ---------------------------------------------- |
| `LvimLspOutlineWinbar`    | blue on tint    | Panel winbar title (full width)                |
| `LvimLspOutlineName`      | fg              | Symbol name                                    |
| `LvimLspOutlineDetail`    | comment         | The dim `detail` virtual text                  |
| `LvimLspOutlineGuide`     | dim comment     | The │ tree guide lines                         |
| `LvimLspOutlineFold`      | blue            | The open/closed fold arrow                     |
| `LvimLspOutlineCursor`    | blue tint       | The symbol under the cursor                    |
| `LvimLspOutlineKindFunc`  | blue            | Function / Method / Constructor                |
| `LvimLspOutlineKindType`  | yellow          | Class / Struct                                 |
| `LvimLspOutlineKindIface` | orange          | Interface / Enum / EnumMember / TypeParameter  |
| `LvimLspOutlineKindVar`   | cyan            | Variable                                       |
| `LvimLspOutlineKindField` | teal            | Field / Property                               |
| `LvimLspOutlineKindConst` | red             | Constant                                       |
| `LvimLspOutlineKindModule`| purple          | Module / Namespace / Package / File            |
| `LvimLspOutlineKindValue` | green           | String / Number / Boolean                      |
| `LvimLspOutlineKindObject`| magenta         | Array / Object / Key / Null                    |
| `LvimLspOutlineKindMisc`  | comment         | Event / Operator (and anything unmapped)       |

#### Code-action lightbulb

| Group                                  | Default color            | Description                          |
| -------------------------------------- | ------------------------ | ------------------------------------ |
| `LvimLspLightbulb`                     | yellow                   | Sign-column glyph                    |
| `LvimLspLightbulbPreferred`            | orange                   | Sign-column glyph (isPreferred)      |
| `LvimLspLightbulbVirtualText`          | yellow on yellow tint    | EOL virtual-text chip                |
| `LvimLspLightbulbVirtualTextPreferred` | orange on orange tint    | EOL virtual-text chip (isPreferred)  |

#### Diagnostics peek filter bar

Per-severity accents come from the editor's `Diagnostic{Error,Warn,Info,Hint}` groups (the palette is
a fallback), so the filter buttons match the diagnostic icons / gutter / virtual text.

| Group                          | State                | Description                                   |
| ------------------------------ | -------------------- | --------------------------------------------- |
| `LvimLspPeekFilter{Sev}`       | inactive             | Severity button (Error/Warn/Info/Hint)        |
| `LvimLspPeekFilter{Sev}Active` | active               | The applied severity filter                   |
| `LvimLspPeekFilter{Sev}HoverActive` | active + hovered | Cursor on the applied severity button         |
| `LvimLspPeekFilterScope`       | inactive             | Scope button (Workspace / Buffer)             |
| `LvimLspPeekFilterScopeActive` | active               | The applied scope                             |
| `LvimLspPeekFilterAllHoverActive` | active + hovered  | Cursor on the applied "All" filter            |

---

### Info window element overrides (`info.highlights`)

Each element of the info window resolves its highlight group through `info.highlights`.
Override individual entries to remap an element to any existing group:

```lua
info = {
    highlights = {
        icon = "LvimLspIcon", -- general icons
        server = "LvimLspInfoServerName", -- server name line
        section = "LvimLspInfoSection", -- section headings
        key = "LvimLspInfoKey", -- key: value pairs
        value = "LvimLspInfoValue", -- values in key: value pairs
        config_key = "LvimLspInfoConfigKey", -- keys inside foldable sections
        separator = "LvimLspInfoSeparator", -- separator lines
        linter = "LvimLspInfoLinter", -- linter entries
        formatter = "LvimLspInfoFormatter", -- formatter entries
        tool = "LvimLspInfoToolName", -- EFM tool names
        buffer = "LvimLspInfoBuffer", -- buffer names
        fold = "LvimLspInfoFold", -- fold indicator icon
    },
}
```

---

### Popup color overrides (`popup_global.highlights`)

`popup_global.highlights` overrides lvim-utils UI colors **only for lvim-lsp popups**.
Other plugins using lvim-utils are unaffected.

```lua
popup_global = {
    highlights = {
        LvimUiNormal = { bg = "NONE" },
        LvimUiNormalFloat = { bg = "NONE" },
        LvimUiBorder = { fg = "#89b4fa" },
        -- any LvimUi* group accepted here
    },
}
```

> **Note** — `highlights` (top-level) registers global named groups via `hl.register()`.
> `popup_global.highlights` creates anonymous inline overrides scoped to this instance.
> Use the former for `LvimLsp*` groups and the latter for `LvimUi*` groups.
