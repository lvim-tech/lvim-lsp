-- lvim-lsp: highlight group definitions.
-- All colors come from lvim-utils.colors so the palette is shared across plugins.
-- Registered via lvim-utils.highlight — survive colorscheme changes.

local c = require("lvim-utils.colors")
local hl = require("lvim-utils.highlight")

return {
	highlights = {
		-- ── Info window ───────────────────────────────────────────────────────
		LvimLspInfoBG = { bg = c.bg_soft_dark, fg = c.fg },
		LvimLspInfoTitle = { fg = c.red, bold = true },
		LvimLspInfoServerName = { fg = c.orange },
		LvimLspInfoSection = { fg = c.blue },
		LvimLspInfoKey = { fg = c.yellow },
		LvimLspInfoValue = { fg = c.fg },
		LvimLspInfoSeparator = { fg = hl.blend(c.blue, c.bg, 0.5) },
		LvimLspInfoLinter = { fg = c.cyan },
		LvimLspInfoFormatter = { fg = c.cyan },
		LvimLspInfoToolName = { fg = c.yellow },
		LvimLspInfoBuffer = { fg = c.teal },
		LvimLspInfoDate = { fg = c.fg_muted },
		LvimLspInfoConfig = { fg = c.fg },
		LvimLspInfoConfigKey = { fg = c.teal },
		LvimLspInfoFold = { fg = c.purple },
		LvimLspIcon = { fg = c.blue },

		-- ── Progress panel ────────────────────────────────────────────────────
		LvimLspProgressIcon = { fg = c.yellow },
		LvimLspProgressServer = { fg = c.purple, bold = true },
		LvimLspProgressTitle = { fg = c.cyan },
		LvimLspProgressDone = { fg = c.green },
		LvimLspProgressMessage = { fg = c.purple },
		LvimLspProgressPct = { fg = c.magenta },

		-- ── Installer panel ───────────────────────────────────────────────────
		LvimLspInstallerIconPending = { fg = c.yellow },
		LvimLspInstallerIconOk = { fg = c.gree },
		LvimLspInstallerIconFail = { fg = c.red },
		LvimLspInstallerTool = { fg = c.purple, bold = true },
		LvimLspInstallerStatusPending = { fg = c.teal },
		LvimLspInstallerStatusOk = { fg = c.green },
		LvimLspInstallerStatusFail = { fg = c.red },
		LvimLspInstallerAction = { fg = c.cyan },
	},
}
