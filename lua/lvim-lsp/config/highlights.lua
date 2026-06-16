-- lvim-lsp: highlight group definitions.
-- All colors come from lvim-utils.colors so the palette is shared across plugins.
-- Registered via lvim-utils.highlight — survive colorscheme changes.
--
-- build() must be a function so each call reads the current palette values.
-- If colors.on_change() fires (palette swap), the caller re-invokes build()
-- and re-registers the groups with the fresh colors.

local c = require("lvim-utils.colors")
local hl = require("lvim-utils.highlight")

local function build()
    -- Blend an accent toward the editor bg — the lvim-utils peek tint convention (STRONG active
    -- cell, light body cell), reused here so the diagnostics filter buttons match the peek chrome.
    local function mtint(color, t)
        return hl.blend(color, c.bg, t)
    end
    return {
        -- ── Diagnostics peek filter buttons (per severity) ────────────────────
        -- fg-only, no background: active = the full severity accent (bold), inactive = the same
        -- accent kept mostly intact (0.6 = 60% accent toward bg) so it stays readable. The "All" /
        -- scope buttons fall back to the generic LvimUiPeekFilter* (blue).
        LvimLspPeekFilterErrorActive = { fg = c.red, bold = true },
        LvimLspPeekFilterError = { fg = mtint(c.red, 0.6) },
        LvimLspPeekFilterWarnActive = { fg = c.orange, bold = true },
        LvimLspPeekFilterWarn = { fg = mtint(c.orange, 0.6) },
        LvimLspPeekFilterInfoActive = { fg = c.blue, bold = true },
        LvimLspPeekFilterInfo = { fg = mtint(c.blue, 0.6) },
        LvimLspPeekFilterHintActive = { fg = c.teal, bold = true },
        LvimLspPeekFilterHint = { fg = mtint(c.teal, 0.6) },

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

        -- ── Progress panel ────────────────────────────────────────────────────
        LvimLspProgressIcon = { fg = c.yellow }, -- spinner → yellow (pending)
        LvimLspProgressServer = { fg = c.purple, bold = true },
        LvimLspProgressTitle = { fg = c.yellow }, -- in-progress title → matches icon
        LvimLspProgressDone = { fg = c.green }, -- done title → matches ok colour
        LvimLspProgressMessage = { fg = c.teal }, -- secondary text
        LvimLspProgressPct = { fg = c.magenta },

        -- ── Document Symbols outline panel ────────────────────────────────────
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
