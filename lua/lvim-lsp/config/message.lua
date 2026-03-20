-- lvim-lsp: notification and debug logging defaults.

return {
	notify = {
		-- Set to false to silence all plugin notifications globally.
		enabled = true,
		-- Minimum level to display (vim.log.levels.*).
		min_level = vim.log.levels.INFO,
		-- Title shown in the notification popup.
		title = "Lvim LSP",
	},

	debug = {
		-- Set to true to enable file-based debug logging.
		enabled = false,
		-- Minimum level to record.
		min_level = vim.log.levels.DEBUG,
		-- Log file: stdpath("state")/lvim-lsp/debug.log
	},
}
