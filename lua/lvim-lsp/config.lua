-- lvim-lsp: default configuration.
-- Loaded once by state.lua; users override via require("lvim-lsp").setup(opts).

return {
	file_types = {},
	server_config_dirs = {},

	popup_global = {
		border = { "", "", "", " ", " ", " ", " ", " " },
		position = "editor",
		width = 0.8,
		max_width = 0.8,
		height = "auto",
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
		},

		highlights = {},
	},

	efm = {
		filetypes = {},
		executable = "efm-langserver",
	},

	installer = {
		popup_width = 80,
		hide_installed_delay = 5,
		popup_title = "LSP INSTALLER",
	},

	info = {
		popup_width = 0.5, -- fraction of editor columns
		popup_title = "LSP SERVERS INFORMATION",
	},

	commands = {},

	diagnostics = {
		popup_title = " Diagnostics",
		show_line = nil,
		goto_next = nil,
		goto_prev = nil,
	},

	colors = {},
	on_attach = nil,
	on_dir_change = nil,
	startup_delay_ms = 100,
	dir_change_delay_ms = 5000,
	dap_local_fn = nil,
}
