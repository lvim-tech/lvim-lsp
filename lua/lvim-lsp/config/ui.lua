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

	installer = {
		popup_width = 0.3,
		done_ttl = 5000,
		popup_title = "LSP INSTALLER",
		spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
		icon_ok = "✓",
		icon_error = "✗",
		-- Appearance of the installer's progress panel in lvim-utils.notify.
		panel = {
			name = "LSP Installer",
			icon = "󰏗",
			header_hl = "LvimNotifyHeaderInfo",
		},
		-- Highlight groups for individual line elements.
		highlights = {
			icon_pending = "LvimLspInstallerIconPending",
			icon_ok = "LvimLspInstallerIconOk",
			icon_fail = "LvimLspInstallerIconFail",
			tool = "LvimLspInstallerTool",
			status_pending = "LvimLspInstallerStatusPending",
			status_ok = "LvimLspInstallerStatusOk",
			status_fail = "LvimLspInstallerStatusFail",
			action = "LvimLspInstallerAction",
		},
	},

	info = {
		popup_title = "LSP SERVERS INFORMATION",
		icons = {
			-- section / item prefixes
			server = "■",
			section = "◆",
			item = "●",
			check = "✓",
			mason = "󰏗",
			fold = "➤",
			-- diagnostic severity
			error = "󰅙",
			warn = "󰀨",
			info = "",
			hint = "",
		},
	},
}
