-- lvim-lsp: highlight group definitions.
-- All colors come from lvim-utils.colors so the palette is shared across plugins.
-- Registered via lvim-utils.highlight — survive colorscheme changes.
--
-- build() must be a function so each call reads the current palette values.
-- If colors.on_change() fires (palette swap), the caller re-invokes build()
-- and re-registers the groups with the fresh colors.
--
---@module "lvim-lsp.config.highlights"

local c = require("lvim-utils.colors")
local hl = require("lvim-utils.highlight")

local function build()
    -- Blend an accent toward the editor bg — the lvim-utils peek tint convention (STRONG active
    -- cell, light body cell), reused here so the diagnostics filter buttons match the peek chrome.
    local function mtint(color, t)
        return hl.blend(color, c.bg, t)
    end
    -- Per-severity accent comes from the EDITOR's diagnostic groups (Diagnostic{Error,Warn,Info,Hint}), so the
    -- filter buttons match the diagnostic row icons / the gutter / virtual text; the palette is only a fallback.
    local function diag(group, fallback)
        local h = vim.api.nvim_get_hl(0, { name = group, link = false })
        return (h and h.fg and ("#%06x"):format(h.fg)) or fallback
    end
    local d_err = diag("DiagnosticError", c.red)
    local d_warn = diag("DiagnosticWarn", c.orange)
    local d_info = diag("DiagnosticInfo", c.blue)
    local d_hint = diag("DiagnosticHint", c.teal)
    return {
        -- ── Diagnostics peek filter buttons (per severity) ────────────────────
        -- fg-only, no background: active = the full severity accent (bold), inactive = the same
        -- accent kept mostly intact (0.6 = 60% accent toward bg) so it stays readable. "All" falls back
        -- to the generic LvimUiPeekFilter* (green); the scope buttons use the blue Scope groups below.
        LvimLspPeekFilterErrorActive = { fg = d_err, bold = true },
        LvimLspPeekFilterError = { fg = mtint(d_err, 0.6) },
        LvimLspPeekFilterWarnActive = { fg = d_warn, bold = true },
        LvimLspPeekFilterWarn = { fg = mtint(d_warn, 0.6) },
        LvimLspPeekFilterInfoActive = { fg = d_info, bold = true },
        LvimLspPeekFilterInfo = { fg = mtint(d_info, 0.6) },
        LvimLspPeekFilterHintActive = { fg = d_hint, bold = true },
        LvimLspPeekFilterHint = { fg = mtint(d_hint, 0.6) },
        -- hover_active: the cursor ON the active button — the accent fg on a SUBTLE 0.3 BG TINT of the SAME
        -- accent, so landing on the applied filter reads as a soft coloured block (one per filter colour).
        LvimLspPeekFilterErrorHoverActive = { fg = d_err, bg = mtint(d_err, 0.3), bold = true },
        LvimLspPeekFilterWarnHoverActive = { fg = d_warn, bg = mtint(d_warn, 0.3), bold = true },
        LvimLspPeekFilterInfoHoverActive = { fg = d_info, bg = mtint(d_info, 0.3), bold = true },
        LvimLspPeekFilterHintHoverActive = { fg = d_hint, bg = mtint(d_hint, 0.3), bold = true },
        LvimLspPeekFilterAllHoverActive = { fg = c.green, bg = mtint(c.green, 0.3), bold = true },
        -- Scope buttons (Workspace / Buffer) — blue, distinct from the green generic + the severities.
        LvimLspPeekFilterScopeActive = { fg = c.blue, bold = true },
        LvimLspPeekFilterScope = { fg = mtint(c.blue, 0.6) },
        LvimLspPeekFilterScopeHoverActive = { fg = c.blue, bg = mtint(c.blue, 0.3), bold = true },

        -- ── Info window ───────────────────────────────────────────────────────
        LvimLspInfoServerName = { fg = c.orange },
        LvimLspInfoSection = { fg = c.blue },
        LvimLspInfoKey = { fg = c.yellow },
        LvimLspInfoValue = { fg = c.fg },
        LvimLspInfoConfigKey = { fg = c.teal }, -- keys inside Server Capabilities / Settings folds
        LvimLspInfoSeparator = { fg = hl.blend(c.blue, c.bg, 0.5) },
        LvimLspInfoLinter = { fg = c.cyan },
        LvimLspInfoFormatter = { fg = c.cyan },
        LvimLspInfoToolName = { fg = c.yellow },
        LvimLspInfoBuffer = { fg = c.teal },
        LvimLspInfoFold = { fg = c.purple }, -- fold indicator icon (➤)
        LvimLspIcon = { fg = c.blue },

        -- ── Code-action lightbulb ─────────────────────────────────────────────
        -- Sign placement is fg-only; the virtual-text chip adds a soft 0.15 bg tint of its own
        -- accent so it reads as a chip at EOL. Preferred (isPreferred) raises yellow → orange.
        LvimLspLightbulb = { fg = c.yellow },
        LvimLspLightbulbPreferred = { fg = c.orange },
        LvimLspLightbulbVirtualText = { fg = c.yellow, bg = mtint(c.yellow, 0.15) },
        LvimLspLightbulbVirtualTextPreferred = { fg = c.orange, bg = mtint(c.orange, 0.15) },

        -- ── Progress panel ────────────────────────────────────────────────────
        LvimLspProgressIcon = { fg = c.yellow }, -- spinner → yellow (pending)
        LvimLspProgressServer = { fg = c.purple, bold = true },
        LvimLspProgressTitle = { fg = c.yellow }, -- in-progress title → matches icon
        LvimLspProgressDone = { fg = c.green }, -- done title → matches ok colour
        LvimLspProgressMessage = { fg = c.teal }, -- secondary text
        LvimLspProgressPct = { fg = c.magenta },

        -- ── Document Symbols outline panel ────────────────────────────────────
        LvimLspOutlineWinbar = { fg = c.blue, bg = mtint(c.blue, 0.4), bold = true }, -- panel winbar title (full width)
        LvimLspOutlineName = { fg = c.fg }, -- symbol name
        LvimLspOutlineDetail = { fg = c.comment }, -- the dim `detail` virtual text
        LvimLspOutlineGuide = { fg = mtint(c.comment, 0.6) }, -- the │ tree guide lines
        LvimLspOutlineFold = { fg = c.blue }, -- the open/closed fold arrow
        LvimLspOutlineCursor = { bg = mtint(c.blue, 0.16), bold = true }, -- the symbol under the cursor
        -- Kind icon colours — one per category, spread across the palette for variety:
        LvimLspOutlineKindFunc = { fg = c.blue }, -- Function / Method / Constructor
        LvimLspOutlineKindType = { fg = c.yellow }, -- Class / Struct
        LvimLspOutlineKindIface = { fg = c.orange }, -- Interface / Enum / EnumMember / TypeParameter
        LvimLspOutlineKindVar = { fg = c.cyan }, -- Variable
        LvimLspOutlineKindField = { fg = c.teal }, -- Field / Property
        LvimLspOutlineKindConst = { fg = c.red }, -- Constant
        LvimLspOutlineKindModule = { fg = c.purple }, -- Module / Namespace / Package / File
        LvimLspOutlineKindValue = { fg = c.green }, -- String / Number / Boolean
        LvimLspOutlineKindObject = { fg = c.magenta }, -- Array / Object / Key / Null
        LvimLspOutlineKindMisc = { fg = c.comment }, -- Event / Operator (and anything unmapped)
    }
end

return {
    build = build,
    force = false, -- true = always override theme-defined groups
}
