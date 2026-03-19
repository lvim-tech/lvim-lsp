-- lvim-lsp: schema resolver for per-server settings forms.
--
-- Two modes:
--   Schema mode  — server config module has a `schema` field (rich form)
--   Raw mode     — no schema; settings are flattened to key-value pairs
--
-- Value resolution order (highest → lowest priority):
--   1. Project override  (.lvim-lsp/servers/<name>.lua)
--   2. Live client       (client.config.settings)
--   3. Module defaults   (mod.lsp.config.settings)
--
---@module "lvim-lsp.core.schema"

local state = require("lvim-lsp.state")
local project = require("lvim-lsp.core.project")

local M = {}

-- ── Dot-path helpers ──────────────────────────────────────────────────────────

--- Read a value from a nested table by dot-path.
--- e.g. get(t, "Lua.hint.enable") → t.Lua.hint.enable
---@param t    table
---@param path string
---@return any
function M.get(t, path)
	if type(t) ~= "table" then
		return nil
	end
	local node = t
	for part in path:gmatch("[^%.]+") do
		if type(node) ~= "table" then
			return nil
		end
		node = node[part]
	end
	return node
end

--- Write a value into a nested table by dot-path, creating missing tables.
--- e.g. set(t, "Lua.hint.enable", true) → t.Lua.hint.enable = true
---@param t     table
---@param path  string
---@param value any
function M.set(t, path, value)
	local parts = vim.split(path, ".", { plain = true })
	local node = t
	for i = 1, #parts - 1 do
		local p = parts[i]
		if type(node[p]) ~= "table" then
			node[p] = {}
		end
		node = node[p]
	end
	node[parts[#parts]] = value
end

-- ── Type inference (raw mode) ─────────────────────────────────────────────────

---@param val any
---@return string  "bool" | "number" | "string" | "list" | "table"
local function infer_type(val)
	local t = type(val)
	if t == "boolean" then
		return "bool"
	end
	if t == "number" then
		return "number"
	end
	if t == "string" then
		return "string"
	end
	if t == "table" then
		-- Array of primitives → list
		if #val > 0 and type(val[1]) ~= "table" then
			return "list"
		end
		return "table"
	end
	return "string"
end

--- Recursively flatten a settings table into a list of schema-like fields.
---@param t      table
---@param prefix string
---@param out    table
local function flatten(t, prefix, out)
	if type(t) ~= "table" then
		return
	end
	for k, v in pairs(t) do
		local path = prefix ~= "" and (prefix .. "." .. k) or k
		local vtype = infer_type(v)
		if vtype == "table" then
			flatten(v, path, out)
		else
			table.insert(out, {
				key = path,
				type = vtype,
				label = path,
			})
		end
	end
	-- Sort for stable display order
	table.sort(out, function(a, b)
		return a.key < b.key
	end)
end

-- ── Server config loader ──────────────────────────────────────────────────────

--- Load the server config module for `server_name`.
--- Tries each dir in state.config.server_config_dirs in order.
---@param server_name string
---@return table|nil
local function load_mod(server_name)
	for _, dir in ipairs(state.config.server_config_dirs) do
		local ok, mod = pcall(require, dir .. "." .. server_name)
		if ok and type(mod) == "table" then
			return mod
		end
	end
	return nil
end

--- Find the live LSP client for `server_name` attached to `bufnr`.
---@param server_name string
---@param bufnr       integer
---@return table|nil
local function live_client(server_name, bufnr)
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
		if client.name == server_name then
			return client
		end
	end
	return nil
end

-- ── Public API ────────────────────────────────────────────────────────────────

---@class LvimLspSchemaField
---@field key     string   Dot-path into settings (e.g. "Lua.hint.enable")
---@field type    string   "bool" | "number" | "string" | "select" | "list"
---@field label   string   Human-readable label
---@field options string[] Only for type = "select"
---@field value   any      Resolved current value
---@field section string   Section header this field belongs to

---@class LvimLspSchemaSection
---@field section string
---@field fields  LvimLspSchemaField[]

--- Resolve the full schema + current values for `server_name`.
---
---@param server_name string
---@param root_dir    string
---@param bufnr       integer
---@return LvimLspSchemaSection[]  sections
---@return table                   merged_settings  (base ← project overrides)
function M.resolve(server_name, root_dir, bufnr)
	local mod = load_mod(server_name)
	local client = live_client(server_name, bufnr)

	-- Build merged settings: module defaults ← live client ← project overrides
	local base = mod and mod.lsp and mod.lsp.config and mod.lsp.config.settings or {}
	local live = client and client.config and client.config.settings or {}
	local override_raw = project.load_server(root_dir, server_name)
	local override = override_raw.settings or {}

	local merged = vim.tbl_deep_extend("force", vim.deepcopy(base), vim.deepcopy(live), vim.deepcopy(override))

	-- ── Schema mode ───────────────────────────────────────────────────────────
	if mod and type(mod.schema) == "table" then
		local sections = {}
		for _, sec in ipairs(mod.schema) do
			local fields = {}
			for _, f in ipairs(sec.fields or {}) do
				table.insert(fields, {
					key = f.key,
					type = f.type,
					label = f.label,
					options = f.options,
					section = sec.section,
					value = M.get(merged, f.key),
				})
			end
			table.insert(sections, { section = sec.section, fields = fields })
		end
		return sections, merged
	end

	-- ── Raw mode ──────────────────────────────────────────────────────────────
	local flat = {}
	flatten(merged, "", flat)

	local fields = {}
	for _, f in ipairs(flat) do
		table.insert(fields, {
			key = f.key,
			type = f.type,
			label = f.label,
			options = nil,
			section = "Settings",
			value = M.get(merged, f.key),
		})
	end

	return { { section = "Settings", fields = fields } }, merged
end

--- Apply a single field change to a settings copy.
--- Returns the updated settings table (does not mutate the input).
---@param settings table
---@param key      string
---@param value    any
---@return table
function M.apply(settings, key, value)
	local updated = vim.deepcopy(settings)
	M.set(updated, key, value)
	return updated
end

return M
