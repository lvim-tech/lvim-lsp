-- lvim-lsp: feature flag defaults.
-- Per-buffer hooks (document_highlight, auto_format, inlay_hints),
-- CodeLens lifecycle and vim.diagnostic configuration.

return {
	features = {
		document_highlight = false,
		auto_format = true,
		inlay_hints = true,
	},

	code_lens = {
		enabled = true,
	},

	diagnostics = {
		popup_title = " Diagnostics",
		show_line = nil,
		goto_next = nil,
		goto_prev = nil,
		virtual_text = nil,
		virtual_lines = nil,
		underline = nil,
		severity_sort = nil,
		update_in_insert = nil,
		signs = nil,
	},
}
