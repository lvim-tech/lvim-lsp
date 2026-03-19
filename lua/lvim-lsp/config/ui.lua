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
			action = "",
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
		done_ttl = 5000,
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
			title = "󰅙 Declined LSP Tools",
			subtitle = "Space = toggle  ·  Enter = re-enable unchecked  ·  q = cancel",
		},
		-- Install-prompt popup shown when opening a file with missing tools.
		-- title_icon is prepended before "Install LSP tools for <filetype>".
		install = {
			title_icon = "",
			subtitle = "Space = toggle  ·  Enter = install checked  ·  q = skip",
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
			-- diagnostic severity
			error = "󰅙",
			warn = "󰀨",
			info = "",
			hint = "",
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
}
