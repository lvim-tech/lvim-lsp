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
        -- Active = the severity accent on a STRONG (0.2) tint of itself, inactive = a light (0.05)
        -- tint. The "All" / scope buttons fall back to the generic LvimUiPeekFilter* (blue).
        LvimLspPeekFilterErrorActive = { fg = c.red, bg = mtint(c.red, 0.2), bold = true },
        LvimLspPeekFilterError = { fg = c.red, bg = mtint(c.red, 0.05) },
        LvimLspPeekFilterWarnActive = { fg = c.orange, bg = mtint(c.orange, 0.2), bold = true },
        LvimLspPeekFilterWarn = { fg = c.orange, bg = mtint(c.orange, 0.05) },
        LvimLspPeekFilterInfoActive = { fg = c.blue, bg = mtint(c.blue, 0.2), bold = true },
        LvimLspPeekFilterInfo = { fg = c.blue, bg = mtint(c.blue, 0.05) },
        LvimLspPeekFilterHintActive = { fg = c.teal, bg = mtint(c.teal, 0.2), bold = true },
        LvimLspPeekFilterHint = { fg = c.teal, bg = mtint(c.teal, 0.05) },

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
    }
end

return {
    build = build,
    force = false, -- true = always override theme-defined groups
}
