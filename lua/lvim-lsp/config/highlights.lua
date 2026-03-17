-- lvim-lsp: default highlight group definitions.
-- Registered via lvim-utils.highlight — survive colorscheme changes.
-- Override any group with explicit { fg = "#hex", bold = true, ... }.

return {
	highlights = {
		LvimLspIcon           = { link = "Function" },
		LvimLspInfoBG         = { link = "NormalFloat" },
		LvimLspInfoTitle      = { link = "DiagnosticError" },
		LvimLspInfoServerName = { link = "DiagnosticWarn" },
		LvimLspInfoSection    = { link = "Function" },
		LvimLspInfoKey        = { link = "String" },
		LvimLspInfoValue      = { link = "Normal" },
		LvimLspInfoSeparator  = { link = "Function" },
		LvimLspInfoLinter     = { link = "Keyword" },
		LvimLspInfoFormatter  = { link = "Keyword" },
		LvimLspInfoToolName   = { link = "String" },
		LvimLspInfoBuffer     = { link = "Special" },
		LvimLspInfoDate       = { link = "Normal" },
		LvimLspInfoConfig     = { link = "Normal" },
		LvimLspInfoConfigKey  = { link = "Special" },
		LvimLspInfoFold       = { link = "DiagnosticHint" },
	},
}
