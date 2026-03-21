-- lvim-lsp: global user settings persistence.
-- Stores feature flags toggled interactively (auto_format, inlay_hints,
-- code_lens, diagnostics virtual display) as JSON in stdpath("data").
-- These take precedence over static user-config defaults, but per-project
-- .lvim-lsp/config.lua can still override them at the buffer level.
--
-- Load order inside lvim-lsp.setup():
--   1. state.configure(user_opts)   ← static defaults + user config
--   2. globals.load()               ← persisted interactive overrides  ← HERE
--   3. features.setup_diagnostics() ← reads the now-updated state
--   4. features.setup_code_lens()   ← reads the now-updated state
--
---@module "lvim-lsp.core.globals"

local state = require("lvim-lsp.state")
local M = {}

---@return string
local function disk_path()
	return vim.fn.stdpath("data") .. "/lvim-lsp-settings.json"
end

--- Read and decode the JSON file; return {} on any error.
---@return table
local function read_disk()
	local ok, lines = pcall(vim.fn.readfile, disk_path())
	if not ok or not lines or #lines == 0 then
		return {}
	end
	local json_ok, data = pcall(vim.json.decode, table.concat(lines, ""))
	return (json_ok and type(data) == "table") and data or {}
end

--- Load persisted globals and apply them on top of state.config.
--- Called once in lvim-lsp.setup(), after state.configure() and before
--- features.setup_diagnostics() / features.setup_code_lens().
function M.load()
	local data = read_disk()
	if vim.tbl_isempty(data) then
		return
	end

	-- features
	if data.auto_format ~= nil then
		state.config.features.auto_format = data.auto_format
	end
	if data.inlay_hints ~= nil then
		state.config.features.inlay_hints = data.inlay_hints
	end
	if data.document_highlight ~= nil then
		state.config.features.document_highlight = data.document_highlight
	end

	-- code_lens
	if data.code_lens ~= nil then
		state.config.code_lens.enabled = data.code_lens
	end

	-- progress
	if data.progress ~= nil then
		state.config.progress.enabled = data.progress
	end

	-- diagnostics (stored as plain booleans; vim.diagnostic.config accepts both
	-- boolean true and table { prefix = "…" } for virtual_text)
	local diag_keys = { "virtual_text", "virtual_lines", "underline", "severity_sort", "update_in_insert" }
	for _, k in ipairs(diag_keys) do
		if data[k] ~= nil then
			state.config.diagnostics[k] = data[k]
		end
	end
end

--- Merge `updates` into the globals file and persist to disk.
--- Only the provided keys are touched; all other persisted values are preserved.
---@param updates table  Flat { key = value } pairs to store
function M.save(updates)
	local existing = read_disk()
	for k, v in pairs(updates) do
		existing[k] = v
	end
	local enc_ok, encoded = pcall(vim.json.encode, existing)
	if enc_ok then
		pcall(vim.fn.writefile, { encoded }, disk_path())
	end
end

return M
