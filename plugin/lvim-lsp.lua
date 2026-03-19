-- lvim-lsp plugin guard.
-- Nothing auto-runs; the user controls everything via require("lvim-lsp").setup(opts).
-- This file exists so lazy.nvim (and other plugin managers) recognise the plugin
-- without requiring an explicit `main` field.
if vim.g.loaded_lvim_lsp then
	return
end
vim.g.loaded_lvim_lsp = true
