-- lvim-lsp: the live UI configuration table (defaults).
-- Holds every user-facing default; state.configure() merges user overrides into it in place via
-- lvim-utils.utils.merge, so every reader (require("lvim-lsp.state").config) sees the effective
-- values. Covers the shared popup chrome (popup_global, forwarded to lvim-ui), the server-
-- management menus, the project panel, the info window, the line-diagnostics float, the progress
-- panel, the location-peek knobs (forwarded to lvim-picker) and the Document Symbols outline.
--
---@module "lvim-lsp.config.ui"

---@class LvimLspPeekAppearance
---@field list_wrap      boolean            Soft-wrap the picker's location list rows
---@field expand         "auto"|"manual"    Group expansion mode (auto = follow cursor)
---@field list_position  "left"|"right"     Which side the list pane docks on
---@field list_width     number             List/preview split fraction (0–1)
---@field preview_height integer            Preview pane height (rows)
---@field icon           string             Nerd glyph fronting the peek title + its dock-stack entry

---@class LvimLspPeekForce
---@field float table Per-open ANCHORED geometry override for the float layout (height, height_auto, width, width_auto, backdrop, auto_hide, keep_focus); empty {} inherits the global
---@field area  table Per-open ANCHORED geometry override for the area layout (full-width — no width/width_auto); empty {} inherits the global
---@field bottom table Per-open ANCHORED geometry override for the bottom layout (full-width — no width/width_auto); empty {} inherits the global

---@class LvimLspPeek
---@field native     boolean                 true = Neovim's built-in handlers; false = the lvim-utils picker
---@field layout     "area"|"float"|"bottom" Which picker layout the peek uses
---@field dock_stack boolean                 true = the peek joins the shared dock STACK (cyclable, one-visible-per-layout); false = geometry-only standalone open
---@field force      LvimLspPeekForce        Per-layout ANCHORED geometry overrides forwarded to lvim-picker (deep-merged over the global dock geometry)
---@field appearance LvimLspPeekAppearance   Appearance forwarded to the lvim-utils picker/peek

---@class LvimLspOutline
---@field position     "right"|"left"  Which side the panel docks on
---@field width        number          Editor-width fraction (or absolute columns if > 1)
---@field title        string|false    Full-width winbar label (false/"" hides it)
---@field follow       boolean         Highlight the symbol under the source cursor
---@field auto_fold    boolean         Accordion: keep only the current symbol's ancestors open
---@field auto_close   boolean         Close the panel after jumping to a symbol
---@field fold_initial "none"|"all"    Initial fold state (all expanded / all collapsed)
---@field detail       boolean         Show each symbol's detail/signature as dim virtual text
---@field source_colors boolean        Colour names/icons from the buffer's own highlights
---@field keys         table<string,string|string[]> Panel keymaps
---@field fold         { open: string, closed: string } Fold arrows
---@field guide        string          Vertical tree-guide glyph
---@field branch       string          Branch glyph (leaf with siblings below)
---@field branch_last  string          Last-branch glyph
---@field icons        table<string,string> SymbolKind → glyph

---@class LvimLspFilterButton
---@field id     string              Button id (matched to a code-side predicate)
---@field label  string             Visible label
---@field key?   string             Hotkey letter to bracket ([X]) + direct activation key
---@field hl?    string             Inactive highlight group
---@field hl_active? string         Active highlight group
---@field hl_hover_active? string   Cursor-on-active highlight group

---@class LvimLspFilterGroup
---@field id      string                Group id (passed to the picker filter spec)
---@field active? string                Default active button id (calls: set at runtime from the direction)
---@field buttons LvimLspFilterButton[] The group's buttons (display only; predicates attached in code)

---@class LvimLspFiltersSymbolsKind
---@field id     string             Group id ("kind")
---@field active string             Default active button id ("all")
---@field all    LvimLspFilterButton The static [A]ll button (per-kind buttons are generated at runtime)

---@class LvimLspFiltersDiagnostics
---@field scope    LvimLspFilterGroup Workspace / Buffer scope toggle
---@field severity LvimLspFilterGroup All / Error / Warn / Info / Hint severity filter

---@class LvimLspFiltersCalls
---@field direction LvimLspFilterGroup Incoming / Outgoing call-direction toggle

---@class LvimLspFiltersSymbols
---@field kind LvimLspFiltersSymbolsKind Symbol-kind filter (static All + dynamic per-kind buttons)

---@class LvimLspFilters
---@field diagnostics LvimLspFiltersDiagnostics Diagnostics picker header filter bar
---@field calls       LvimLspFiltersCalls        Call-hierarchy picker header filter bar
---@field symbols     LvimLspFiltersSymbols      Symbols picker header filter bar

---@class LvimLspDiagnosticsListKeys
---@field code_action string|string[] Jump to the focused diagnostic's location and open LSP code actions there
---@field yank        string|string[] Copy the focused diagnostic's message to the clipboard register
---@field quickfix    string|string[] Send the marked diagnostics (or, if none marked, all) to the quickfix list

---@class LvimLspDiagnosticsList
---@field keys LvimLspDiagnosticsListKeys Row-action keys on the diagnostics-list picker (ui/diagnostics_list.lua)

---@class LvimLspDiagnostics
---@field marker table                    Line-diagnostics float selection markers (icon / inactive_icon)
---@field list   LvimLspDiagnosticsList   Diagnostics-list picker row actions

---@class LvimLspLightbulb
---@field enabled        boolean               Show the indicator at all (false = the module is inert)
---@field placement      "virtual_text"|"sign" Where the hint renders (EOL chip / sign column)
---@field icon           string                Nerd glyph for the hint (single-width)
---@field update_ms      integer               Debounce (ms) between a cursor event and the probe
---@field only           string[]|nil          CodeActionKind filter (nil = all kinds)
---@field show_preferred boolean               Orange accent when any action is marked isPreferred

---@class LvimLspConfig
---@field popup_global table          Shared popup chrome forwarded to lvim-ui
---@field form        table           Form behaviour (after_apply: "Stay"|"Close")
---@field footer_separator string     Group separator glyph for the lvim-lsp action-footer bars
---@field footers     table<string,string[][]> Button lists (groups of action ids) per lvim-lsp footer bar
---@field filters     LvimLspFilters  Header filter-bar button lists for the picker-backed UIs
---@field menus       table           Titles/subtitles for the server-management multiselect popups
---@field project     table           Project settings panel chrome (title icon, per-tab labels/icons)
---@field info        table           Info window chrome (title, icons, highlight groups)
---@field diagnostics LvimLspDiagnostics Line-diagnostics float markers + diagnostics-list row actions
---@field progress    table           Progress panel (spinner, done icon, render limit, chrome, highlights)
---@field peek        LvimLspPeek     Location-peek knobs (backend + layout + appearance)
---@field outline     LvimLspOutline  Document Symbols outline panel
---@field hover       table           Hover float (enabled/title/wrap)
---@field lightbulb   LvimLspLightbulb Code-action availability indicator (ui/lightbulb.lua)

---@type LvimLspConfig
return {
    popup_global = {
        -- No border here: the chassis owns the frame border (the shared full-ring `surface.FRAME_BORDER`),
        -- so every presenter (tabs / info / select …) renders the native border-title on it. A per-plugin
        -- border override would only re-introduce a divergent ring — the unified model forbids it.
        position = "editor",
        width = 0.8,
        max_width = 0.8,
        height = 0.8,
        max_height = 0.8,
        max_items = nil,
        close_keys = { "q", "<Esc>" },
        markview = false,

        icons = {
            bool_on = "󰄬",
            bool_off = "󰍴",
            select = "󰘮",
            number = "󰎠",
            string = "󰬴",
            action = "",
            spacer = "   ──────",
            multi_selected = "󰄬",
            multi_empty = "󰍴",
            current = "➤",
        },

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

        keys = {
            down = "j",
            up = "k",
            confirm = "<CR>",
            cancel = "<Esc>",
            close = "q",

            tabs = {
                next = "l",
                prev = "h",
            },

            select = {
                confirm = "<CR>",
                cancel = "<Esc>",
            },

            multiselect = {
                toggle = "<Space>",
                confirm = "<CR>",
                cancel = "<Esc>",
            },

            list = {
                next_option = "<Tab>",
                prev_option = "<BS>",
            },

            back = "u",
        },

        highlights = {},
    },

    form = {
        after_apply = "Close", -- "Stay" | "Close"
    },

    -- ── Action-footer bars ──────────────────────────────────────────────────────
    -- The BUTTON LISTS (groups of action ids) for every lvim-lsp-BUILT footer bar — the same model the
    -- lvim-utils picker (config.picker.footer) and shell (config.footer_bar) use: the config holds WHICH
    -- buttons appear and how they are GROUPED, the code holds the REGISTRY (id → { key, name, run }) and
    -- renders it with `lvim-ui.surface.bar`. Reorder / regroup / hide buttons here; a `●` separator
    -- (footer_separator) is auto-inserted between non-empty groups. (Filter bars in the diagnostics / call
    -- hierarchy / symbols pickers are NOT here — those are the lvim-utils picker's own `filters` model.)
    footer_separator = "●",
    footers = {
        -- The project settings panel (ui/project.lua) — a plain close-only bar so the geometry never jumps.
        project = { { "close" } },
        -- The outline keymap cheatsheet (ui/outline.lua `show_help`) — likewise close-only.
        outline_help = { { "close" } },
    },

    -- ── Header filter bars ──────────────────────────────────────────────────────
    -- The BUTTON LISTS for the picker-backed UIs' header filter bars (rendered by the lvim-utils picker's
    -- own `lvim-ui.filters` model). Only the DISPLAY parts live here — the button `id`, `label`, `key`
    -- (bracketed hotkey) and the highlight-group names (`hl` inactive / `hl_active` / `hl_hover_active`). The
    -- code owns the SEMANTICS: it attaches each button's `predicate`, manages the runtime `active` state, and
    -- (symbols) appends the per-kind buttons discovered in the results. Reorder / rename / recolour filters
    -- here without touching the filtering logic.
    filters = {
        -- Diagnostics picker (ui/diagnostics_list.lua): SCOPE toggle + SEVERITY filter.
        diagnostics = {
            scope = {
                id = "scope",
                active = "workspace",
                buttons = {
                    -- `o` (not `w`): W is the Warn severity hotkey, so bracket the `o` — W[o]rkspace.
                    {
                        id = "workspace",
                        label = "Workspace",
                        key = "o",
                        hl = "LvimLspPeekFilterScope",
                        hl_active = "LvimLspPeekFilterScopeActive",
                        hl_hover_active = "LvimLspPeekFilterScopeHoverActive",
                    },
                    {
                        id = "buffer",
                        label = "Buffer",
                        key = "b",
                        hl = "LvimLspPeekFilterScope",
                        hl_active = "LvimLspPeekFilterScopeActive",
                        hl_hover_active = "LvimLspPeekFilterScopeHoverActive",
                    },
                },
            },
            severity = {
                id = "severity",
                active = "all",
                buttons = {
                    { id = "all", label = "All", key = "a", hl_hover_active = "LvimLspPeekFilterAllHoverActive" },
                    {
                        id = "error",
                        label = "Error",
                        key = "e",
                        hl = "LvimLspPeekFilterError",
                        hl_active = "LvimLspPeekFilterErrorActive",
                        hl_hover_active = "LvimLspPeekFilterErrorHoverActive",
                    },
                    {
                        id = "warn",
                        label = "Warn",
                        key = "w",
                        hl = "LvimLspPeekFilterWarn",
                        hl_active = "LvimLspPeekFilterWarnActive",
                        hl_hover_active = "LvimLspPeekFilterWarnHoverActive",
                    },
                    {
                        id = "info",
                        label = "Info",
                        key = "i",
                        hl = "LvimLspPeekFilterInfo",
                        hl_active = "LvimLspPeekFilterInfoActive",
                        hl_hover_active = "LvimLspPeekFilterInfoHoverActive",
                    },
                    -- `n` (not `h`): Hi[n]t — keep `h` as the cursor-left motion.
                    {
                        id = "hint",
                        label = "Hint",
                        key = "n",
                        hl = "LvimLspPeekFilterHint",
                        hl_active = "LvimLspPeekFilterHintActive",
                        hl_hover_active = "LvimLspPeekFilterHintHoverActive",
                    },
                },
            },
        },
        -- Call-hierarchy picker (ui/calls.lua): Incoming / Outgoing (default active set at runtime).
        calls = {
            direction = {
                id = "direction",
                buttons = {
                    { id = "incoming", label = "Incoming", key = "i" },
                    { id = "outgoing", label = "Outgoing", key = "o" },
                },
            },
        },
        -- Symbols picker (ui/symbols.lua): the static [A]ll button; per-kind buttons are appended in code
        -- from the SymbolKinds actually present (they carry no hotkey — reached with l/h on the bar).
        symbols = {
            kind = {
                id = "kind",
                active = "all",
                all = { id = "all", label = "All", key = "a" },
            },
        },
    },

    -- ── Server management popups ────────────────────────────────────────────────

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
        -- Declined-tools management popup.
        declined = {
            title = "󰅙 Declined Packages",
            subtitle = "uncheck to re-enable for its filetype",
        },
    },

    -- ── Project settings panel ──────────────────────────────────────────────────

    project = {
        -- Icon prepended to the panel title ("󰒓 Project — <root>").
        title_icon = "󰒓",
        -- Per-tab label and icon for the main project panel.
        tabs = {
            servers = { label = "LSP Servers", icon = "󰒋" },
            formatters = { label = "Formatters", icon = "󰒡" },
            linters = { label = "Linters", icon = "󱉶" },
            filetypes = { label = "Filetypes", icon = "󰈔" },
            global = { label = "Global", icon = "󰒓" },
        },
    },

    -- ── Info window ─────────────────────────────────────────────────────────────

    info = {
        popup_title = "󰨸 LSP SERVERS INFORMATION",
        icons = {
            -- section / item prefixes (Nerd Font: filled square / rhombus / circle for the client → section → item tree)
            server = "󰝤",
            section = "󰜁",
            item = "󰝥",
            check = "󰄬",
            mason = "󰏗",
            fold = "➤",
            -- Diagnostic severity glyphs. These are the FALLBACK ONLY: the info panel and the diagnostics
            -- navigator first honour YOUR Neovim signs (vim.diagnostic.config().signs.text, then any legacy
            -- DiagnosticSign* signs) and use these glyphs only when you have set neither. (Copied from the
            -- user's icon set so the out-of-the-box look matches it.)
            error = "",
            warn = "",
            info = "",
            hint = "󰌵",
        },
        -- Highlight groups for info window elements.
        -- Override any entry to use your own group name.
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

    -- ── Line-diagnostics float (lvim-lsp/ui/diagnostic.lua) ──────────────────────
    -- The SELECTED diagnostic is marked with `icon`, tinted (severity fg + a bg tint); the others with
    -- `inactive_icon`, plain, in their own severity colour. Same dot by default; the tint tells them apart.
    diagnostics = {
        -- Line-diagnostics float width cap: <= 1 = fraction of the screen, else absolute columns.
        max_width = 0.8,
        -- Padding { front, back } (spaces) around each diagnostic row text, independent of the marker.
        text_pad = { 1, 1 },
        marker = {
            icon = "",
            inactive_icon = "",
            pad = { 1, 1 }, -- padding { front, back } (spaces) around the marker glyph
            bg_tint = 0.3, -- bg tint of the selected marker's fg (0 = no bg)
        },
        -- Diagnostics-list picker (ui/diagnostics_list.lua) row actions — each acts on the FOCUSED
        -- diagnostic. Configurable; a value is any lhs the picker's per-call `keys` accept (a single
        -- key). The footer chips follow these automatically (the picker derives its hints from `keys`).
        list = {
            keys = {
                code_action = "<C-a>", -- jump to the diagnostic's location and open LSP code actions there
                yank = "<C-y>", -- copy the focused diagnostic's message to the clipboard register
                quickfix = "<C-q>", -- the marked diagnostics (or, if none marked, all) → the quickfix list
            },
        },
    },

    -- ── Progress panel (rendered by lvim-lsp/ui/progress.lua) ───────────────────

    progress = {
        -- Spinner frames cycled while work is in progress (Nerd Font circle-slice pie fill, 8 frames).
        spinner = { "󰪞", "󰪟", "󰪠", "󰪡", "󰪢", "󰪣", "󰪤", "󰪥" },
        -- Icon shown once an entry completes.
        done_icon = "󰄬",
        -- Maximum number of concurrent entries shown in the panel.
        render_limit = 4,
        -- Panel chrome in lvim-hud.notify.
        panel = {
            name = "LSP Progress",
            icon = "",
            header_hl = "LvimNotifyHeaderInfo",
        },
        -- Highlight groups for individual line elements.
        highlights = {
            icon = "LvimLspProgressIcon",
            server = "LvimLspProgressServer",
            title = "LvimLspProgressTitle",
            done = "LvimLspProgressDone",
            message = "LvimLspProgressMessage",
            percentage = "LvimLspProgressPct",
        },
    },

    -- LOCATION PEEK ----------------------------------------------------------
    -- How the "go to / list" navigation features (definition, references, diagnostics, call hierarchy,
    -- symbols, …) are presented. TWO global knobs, overridable PER CALL via the public API (e.g. a keymap
    -- `require("lvim-lsp").definition({ layout = "float" })`) or a command arg (`:LvimLsp definition native`):
    --   native = false → OUR system (the public lvim-utils picker / peek) — the DEFAULT, the modern layout
    --   native = true  → Neovim's built-in handlers (quickfix / direct jump) everywhere
    --   layout         → which picker layout: "area" (cmdheight/msgarea zone, the DEFAULT) | "float" | "bottom"
    -- A single location result always jumps directly, regardless.
    peek = {
        native = false,
        layout = "area",

        -- true = full dock-STACK consumer: the peek is a managed entry in the shared lvim-utils dock stack
        -- (cyclable <Leader>n/p/x/m, :LvimDock, one-visible-per-layout, no overlap with a docked picker /
        -- terminal). false = geometry-only: the peek still uses the central dock.slot size/backdrop but opens
        -- standalone and is NOT registered in the stack. Forwarded to lvim-picker.open as opts.dock_stack.
        dock_stack = true,

        -- Per-layout ANCHORED geometry overrides, forwarded to lvim-picker.open as opts.force and deep-merged
        -- per field OVER the global `lvim-utils.config.dock.geometry.<layout>`; empty {} = inherit the global
        -- unchanged. Each layout may carry: height, height_auto, backdrop = { enabled, mode, dim = { amount },
        -- darken = { amount } }, auto_hide, keep_focus. FLOAT ALSO: width, width_auto. area/bottom are ALWAYS
        -- full-width — width/width_auto there are ignored.
        force = { float = {}, area = {}, bottom = {} },

        -- Appearance, forwarded to lvim-utils `ui.peek` (see its config for every field).
        appearance = {
            -- Soft-wrap the picker's location list rows (no "↳" marker) so a match far to the right of a
            -- long code line stays visible. false = truncate.
            list_wrap = true,
            -- "auto": only the focused file group is open and follows the cursor.
            -- "manual": toggle groups open/closed by click or <CR> on their header.
            expand = "manual",
            list_position = "left",
            list_width = 0.4, -- 40% list / 60% preview; drag the divider to adjust live
            preview_height = 16,
            -- Nerd glyph shown before the peek title AND as the peek's entry in the shared dock stack
            -- (lvim-utils.dock — the `<Leader>m` menu). Every location/diagnostics peek shares ONE stable
            -- dock entry (`lvim-picker:lsp-peek`), so this one glyph identifies the peek there.
            icon = "󰈭",
        },
    },

    -- OUTLINE ----------------------------------------------------------------
    -- Document Symbols outline (:LvimLsp outline) — a persistent side-split panel (neo-tree style)
    -- that lists the current file's symbol tree and follows the cursor.
    outline = {
        position = "right", -- "right" | "left" — which side the panel docks on
        width = 0.25, -- fraction of the editor width (or absolute columns if > 1)
        title = "LVIM LSP OUTLINE", -- full-width winbar label (blue text on a blue tint); false/"" hides it

        follow = true, -- highlight the symbol under the cursor as you move in the source
        auto_fold = true, -- accordion ON by default: keep only the current symbol's ancestors open.
        -- Any manual fold (W/E/h/l/<Tab>) suspends it; the `fold_auto` key (A) resumes it.
        auto_close = false, -- close the panel after jumping to a symbol
        fold_initial = "none", -- "none" (all expanded) | "all" (all collapsed)
        detail = true, -- show each symbol's detail/signature as dim virtual text
        source_colors = true, -- colour each name + icon with the symbol's own colour from the buffer
        --                       (treesitter / LSP semantic tokens); falls back to the per-kind colours
        -- Blank columns around the tree ROWS (the title band always spans the full width). Overrides the shared
        -- `lvim-ui.config.tree.padding`; TWO on the right here because a symbol's `detail` (its signature) is
        -- dense and reaches the clip limit on nearly every row — a single column reads as touching the edge.
        padding = { left = 1, right = 2 },
        scrollbar = false, -- right-edge thumb while the outline overflows the panel
        -- Panel keymaps (all configurable; a key may be a string or a list of strings). Press `?`
        -- inside the panel for the live cheatsheet.
        keys = {
            goto_location = "<CR>", -- jump to the symbol (honours `auto_close`)
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
            fold_reset = "R", -- reset folds to `fold_initial`
            fold_auto = "A", -- (re)enable the accordion auto-fold
            hover_symbol = "<C-space>", -- LSP hover on the symbol
            code_actions = "a", -- code actions at the symbol
            rename_symbol = "r", -- rename the symbol
            help = "g?", -- show this cheatsheet (g? = the fugitive / oil help convention)
            close = { "q", "<Esc>" }, -- close the panel
        },
        -- Tree chrome glyphs (all configurable): the fold arrows and the vertical guide line.
        fold = { open = "", closed = "" },
        guide = "│", -- vertical continuation line
        branch = "├", -- a leaf with siblings below it
        branch_last = "└", -- the last leaf in its group
        -- SymbolKind → glyph. Keyed by the LSP SymbolKind name.
        icons = {
            File = "󰈙",
            Module = "󰏗",
            Namespace = "󰦮",
            Package = "󰏖",
            Class = "󰠱",
            Method = "󰆧",
            Property = "󰜢",
            Field = "󰜢",
            Constructor = "󰙴",
            Enum = "󰕘",
            Interface = "󰜰",
            Function = "󰊕",
            Variable = "󰀫",
            Constant = "󰏿",
            String = "󰉿",
            Number = "󰎠",
            Boolean = "󰐾",
            Array = "󰅪",
            Object = "󰅩",
            Key = "󰌋",
            Null = "󰟢",
            EnumMember = "󰦨",
            Struct = "󰙅",
            Event = "󰉁",
            Operator = "󰆕",
            TypeParameter = "󰫣",
        },
    },

    -- HOVER ------------------------------------------------------------------
    -- When enabled, `:LvimLsp hover` renders the hover documentation in a themed lvim-utils
    -- info float (house chrome) instead of Neovim's built-in popup. When false (default), the
    -- native `vim.lsp.buf.hover` is used.
    hover = {
        enabled = false,
        title = " Hover",
        wrap = true, -- soft-wrap the hover float (consumed by ui/hover.lua)
        max_width = 80, -- hover float width cap: ≤ 1 = fraction of the screen, else absolute columns
        max_height = 0.4, -- hover float height cap: ≤ 1 = fraction of the screen, else absolute rows
    },

    -- LIGHTBULB --------------------------------------------------------------
    -- Code-action availability indicator (ui/lightbulb.lua): when the cursor rests on a line where an
    -- attached client offers textDocument/codeAction, a 󰌵 hint appears — EOL virtual text (a soft
    -- yellow chip, right-aligned) or a sign-column glyph. Debounced on CursorHold/CursorMoved; the
    -- in-flight request is cancelled before the next fires. Per-buffer opt-out:
    -- `vim.b.lvim_lsp_lightbulb_disable = true`.
    lightbulb = {
        enabled = true,
        placement = "virtual_text", -- "virtual_text" (chip right after the line text) | "sign" (sign column)
        icon = "󰌵",
        -- LEADING-throttle interval (ms) between probes. 0 = probe on EVERY cursor move immediately (the
        -- snappiest — only the LSP round-trip remains; a stale in-flight probe is cancelled + generation-
        -- guarded, so it never floods). Raise it (e.g. 60-120) to cut the request rate on a slow server.
        update_ms = 0,
        -- CodeActionKind filter forwarded as context.only — nil = all kinds. Narrow it (e.g.
        -- { "quickfix", "refactor" }) so formatting-ish source actions don't light it constantly.
        only = nil,
        -- When any offered action is marked isPreferred, raise the accent yellow → orange.
        show_preferred = true,
    },
}
