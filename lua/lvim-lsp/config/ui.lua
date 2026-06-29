-- lvim-lsp: UI defaults.
-- popup_global (passed to lvim-utils), installer popup, info popup.

return {
    popup_global = {
        border = { "", "", "", " ", " ", " ", " ", " " },
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
            -- section / item prefixes
            server = "■",
            section = "◆",
            item = "●",
            check = "✓",
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
        marker = {
            icon = "",
            inactive_icon = "",
        },
    },

    -- ── Progress panel (rendered by lvim-lsp/ui/progress.lua) ───────────────────

    progress = {
        -- Spinner frames cycled while work is in progress.
        spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
        -- Icon shown once an entry completes.
        done_icon = "✓",
        -- Maximum number of concurrent entries shown in the panel.
        render_limit = 4,
        -- Panel chrome in lvim-utils.notify.
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
            float = {
                width = 0.85,
                height = 0.8,
                zindex = 50,
                backdrop = true,
                backdrop_blend = 40,
            },
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
    },
}
