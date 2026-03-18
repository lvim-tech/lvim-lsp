-- lvim-lsp: LSP progress tracking defaults.

return {
	progress = {
		-- Set to false to disable the entire progress subsystem.
		enabled = true,
		-- Server names to silently ignore (e.g. { "null-ls" }).
		ignore = {},
		-- Milliseconds to keep a "done" entry visible before removing it.
		done_ttl = 5000,
		-- Spinner frames cycled while work is in progress.
		spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
		-- Icon shown once work is complete (shown for done_ttl ms).
		done_icon = "✓",
		-- Maximum number of concurrent entries shown in the panel.
		render_limit = 4,
		-- Progress panel appearance in lvim-utils.notify.
		-- name:       text shown in the panel header bar.
		-- icon:       icon shown in the header.
		-- header_hl:  highlight group for the header bar.
		panel = {
			name = "LSP Progress",
			icon = "󱦟",
			header_hl = "LvimNotifyHeaderInfo",
		},
		-- Highlight groups for individual line elements.
		-- Set any key to nil or false to disable that element's highlight.
		highlights = {
			icon = "Question", -- spinner / done icon
			server = "Title", -- LSP server name
			title = "WarningMsg", -- progress title (in-progress)
			done = "Constant", -- progress title / icon (done)
			message = "Comment", -- detail message text
			percentage = "Special", -- percentage number
		},
	},
}
