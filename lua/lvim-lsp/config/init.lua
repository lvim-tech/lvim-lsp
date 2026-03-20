-- lvim-lsp: default configuration entry point.
-- Merges logical config sections into a single table.
-- Loaded once by state.lua; users override via require("lvim-lsp").setup(opts).

local lsp = require("lvim-lsp.config.lsp")
local ui = require("lvim-lsp.config.ui")
local features = require("lvim-lsp.config.features")
local highlights = require("lvim-lsp.config.highlights")
local progress = require("lvim-lsp.config.progress")
local message = require("lvim-lsp.config.message")

---@type LvimLspConfig
local M = vim.tbl_deep_extend("force", lsp, ui, features, progress, message) --[[@as LvimLspConfig]]
M.build = highlights.build
M.force = highlights.force
return M
