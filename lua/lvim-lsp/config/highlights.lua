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
	return {
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

		-- ── Installer panel ───────────────────────────────────────────────────
		LvimLspInstallerIconPending = { fg = c.yellow },
		LvimLspInstallerIconOk = { fg = c.green },
		LvimLspInstallerIconFail = { fg = c.red },
		LvimLspInstallerTool = { fg = c.purple, bold = true },
		LvimLspInstallerStatusPending = { fg = c.yellow }, -- matches IconPending
		LvimLspInstallerStatusOk = { fg = c.green }, -- matches IconOk
		LvimLspInstallerStatusFail = { fg = c.red }, -- matches IconFail
		LvimLspInstallerAction = { fg = c.teal }, -- secondary text
	}
end

return {
	build = build,
	force = false, -- true = always override theme-defined groups
}
