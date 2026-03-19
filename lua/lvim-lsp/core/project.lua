-- lvim-lsp: project-local configuration loader/writer.
--
-- Directory layout (preferred):
--   .lvim-lsp/
--   ├── config.lua          ← project overrides (disable, auto_format, …)
--   ├── servers/
--   │   └── <server>.lua    ← per-server settings overrides
--   └── filetypes/
--       └── <ft>.lua        ← per-filetype editor settings
--
-- Legacy: .lvim-lsp.lua in the project root is still read as a fallback
-- for config.lua when the directory form does not exist.
--
---@module "lvim-lsp.core.project"

local M = {}

-- ── Constants ─────────────────────────────────────────────────────────────────

local DIR = ".lvim-lsp"
local LEGACY_FILE = ".lvim-lsp.lua"
local CONFIG_FILE = "config.lua"
local SERVERS_DIR = "servers"
local FT_DIR = "filetypes"
local EFM_DIR = "efm"

-- ── Cache ─────────────────────────────────────────────────────────────────────

---@type table<string, table>   root_dir → config
local _config_cache = {}
---@type table<string, table>   root_dir/server → settings
local _server_cache = {}
---@type table<string, table>   root_dir/ft → settings
local _ft_cache = {}
---@type table<string, table>   root_dir/tool → overrides
local _efm_tool_cache = {}

-- ── Private helpers ───────────────────────────────────────────────────────────

--- Ensure a directory exists (creates parent dirs as needed).
---@param path string
local function ensure_dir(path)
	vim.fn.mkdir(path, "p")
end

--- Load a Lua file that returns a table.
--- Returns an empty table when the file is absent or invalid.
---@param path string
---@return table
local function load_file(path)
	if vim.fn.filereadable(path) ~= 1 then
		return {}
	end
	local ok, result = pcall(dofile, path)
	return (ok and type(result) == "table") and result or {}
end

--- Merge `override` into `base`: dicts are merged recursively, arrays replaced wholesale.
---@param base     table
---@param override table
---@return table
local function deep_merge(base, override)
	local result = vim.deepcopy(base)
	for k, v in pairs(override) do
		if type(v) == "table" and type(result[k]) == "table" and not vim.islist(v) then
			result[k] = deep_merge(result[k], v)
		else
			result[k] = vim.deepcopy(v)
		end
	end
	return result
end

--- Serialize a Lua value to a string (supports bool, number, string, table).
---@param val    any
---@param indent? string
---@return string
local function serialize(val, indent)
	indent = indent or ""
	local t = type(val)
	if t == "boolean" then
		return tostring(val)
	elseif t == "number" then
		return tostring(val)
	elseif t == "string" then
		return string.format("%q", val)
	elseif t == "table" then
		local inner = indent .. "    "
		local is_array = #val > 0
		local parts = {}
		if is_array then
			for _, v in ipairs(val) do
				table.insert(parts, inner .. serialize(v, inner))
			end
		else
			local keys = vim.tbl_keys(val)
			table.sort(keys, function(a, b)
				return tostring(a) < tostring(b)
			end)
			for _, k in ipairs(keys) do
				local key = type(k) == "string" and (k:match("^[%a_][%w_]*$") and k or string.format("[%q]", k))
					or string.format("[%d]", k)
				table.insert(parts, inner .. key .. " = " .. serialize(val[k], inner))
			end
		end
		if #parts == 0 then
			return "{}"
		end
		return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
	end
	return "nil"
end

--- Write `data` as a Lua return-table to `path`.
---@param path string
---@param data table
---@return boolean ok
local function write_file(path, data)
	local content = "return " .. serialize(data) .. "\n"
	local ok = pcall(vim.fn.writefile, vim.split(content, "\n"), path)
	return ok
end

-- ── Path helpers ──────────────────────────────────────────────────────────────

---@param root_dir string
---@return string
local function dir_path(root_dir)
	return root_dir .. "/" .. DIR
end

---@param root_dir string
---@return string
local function config_path(root_dir)
	return dir_path(root_dir) .. "/" .. CONFIG_FILE
end

---@param root_dir    string
---@param server_name string
---@return string
local function server_path(root_dir, server_name)
	return dir_path(root_dir) .. "/" .. SERVERS_DIR .. "/" .. server_name .. ".lua"
end

---@param root_dir string
---@param ft       string
---@return string
local function ft_path(root_dir, ft)
	return dir_path(root_dir) .. "/" .. FT_DIR .. "/" .. ft .. ".lua"
end

---@param root_dir  string
---@param tool_name string
---@return string
local function efm_tool_path(root_dir, tool_name)
	return dir_path(root_dir) .. "/" .. EFM_DIR .. "/" .. tool_name .. ".lua"
end

-- ── Public: config (project overrides) ───────────────────────────────────────

--- Load (and cache) the project config for `root_dir`.
--- Prefers .lvim-lsp/config.lua; falls back to legacy .lvim-lsp.lua.
---@param root_dir string
---@return table
function M.load(root_dir)
	if _config_cache[root_dir] ~= nil then
		return _config_cache[root_dir]
	end
	local cfg = load_file(config_path(root_dir))
	if vim.tbl_isempty(cfg) then
		cfg = load_file(root_dir .. "/" .. LEGACY_FILE)
	end
	_config_cache[root_dir] = cfg
	return cfg
end

--- Persist project config overrides to .lvim-lsp/config.lua.
---@param root_dir string
---@param data     table
---@return boolean
function M.save(root_dir, data)
	ensure_dir(dir_path(root_dir))
	local ok = write_file(config_path(root_dir), data)
	if ok then
		_config_cache[root_dir] = data
	end
	return ok
end

--- Invalidate cached project config.
---@param root_dir string
function M.invalidate(root_dir)
	_config_cache[root_dir] = nil
end

--- Returns the path to .lvim-lsp/config.lua (creates dir if needed).
---@param root_dir string
---@return string
function M.config_path(root_dir)
	return config_path(root_dir)
end

--- Returns true when `server_name` is listed in the project's `disable` array.
---@param root_dir    string
---@param server_name string
---@return boolean
function M.is_server_disabled(root_dir, server_name)
	local cfg = M.load(root_dir)
	return type(cfg.disable) == "table" and vim.tbl_contains(cfg.disable, server_name)
end

--- Returns the effective value of a feature flag for a project root.
---@param root_dir     string
---@param key          string
---@param global_value any
---@return any
function M.get_feature(root_dir, key, global_value)
	local cfg = M.load(root_dir)
	if cfg[key] ~= nil then
		return cfg[key]
	end
	return global_value
end

-- ── Public: per-server settings ───────────────────────────────────────────────

--- Load (and cache) per-server settings overrides for `root_dir`.
---@param root_dir    string
---@param server_name string
---@return table
function M.load_server(root_dir, server_name)
	local key = root_dir .. "/" .. server_name
	if _server_cache[key] ~= nil then
		return _server_cache[key]
	end
	local data = load_file(server_path(root_dir, server_name))
	_server_cache[key] = data
	return data
end

--- Persist per-server settings to .lvim-lsp/servers/<name>.lua.
--- Merges `data` into the existing file so that settings from other tabs are preserved.
---@param root_dir    string
---@param server_name string
---@param data        table
---@return boolean
function M.save_server(root_dir, server_name, data)
	ensure_dir(dir_path(root_dir) .. "/" .. SERVERS_DIR)
	local path = server_path(root_dir, server_name)
	local existing = load_file(path)
	local merged = deep_merge(existing, data)
	local ok = write_file(path, merged)
	if ok then
		_server_cache[root_dir .. "/" .. server_name] = merged
	end
	return ok
end

--- Invalidate cached per-server settings.
---@param root_dir    string
---@param server_name string
function M.invalidate_server(root_dir, server_name)
	_server_cache[root_dir .. "/" .. server_name] = nil
end

-- ── Public: per-filetype settings ─────────────────────────────────────────────

--- Load (and cache) per-filetype editor settings for `root_dir`.
---@param root_dir string
---@param ft       string
---@return table
function M.load_ft(root_dir, ft)
	local key = root_dir .. "/" .. ft
	if _ft_cache[key] ~= nil then
		return _ft_cache[key]
	end
	local data = load_file(ft_path(root_dir, ft))
	_ft_cache[key] = data
	return data
end

--- Persist per-filetype settings to .lvim-lsp/filetypes/<ft>.lua.
---@param root_dir string
---@param ft       string
---@param data     table
---@return boolean
function M.save_ft(root_dir, ft, data)
	ensure_dir(dir_path(root_dir) .. "/" .. FT_DIR)
	local ok = write_file(ft_path(root_dir, ft), data)
	if ok then
		_ft_cache[root_dir .. "/" .. ft] = data
	end
	return ok
end

--- Invalidate cached per-filetype settings.
---@param root_dir string
---@param ft       string
function M.invalidate_ft(root_dir, ft)
	_ft_cache[root_dir .. "/" .. ft] = nil
end

-- ── Public: per-EFM-tool overrides ────────────────────────────────────────────

--- Load (and cache) per-EFM-tool project overrides for `root_dir`.
--- Stored under .lvim-lsp/efm/<tool>.lua as { enabled = bool, command = string }.
---@param root_dir  string
---@param tool_name string
---@return table
function M.load_efm_tool(root_dir, tool_name)
	local key = root_dir .. "/" .. tool_name
	if _efm_tool_cache[key] ~= nil then
		return _efm_tool_cache[key]
	end
	local data = load_file(efm_tool_path(root_dir, tool_name))
	_efm_tool_cache[key] = data
	return data
end

--- Persist per-EFM-tool overrides to .lvim-lsp/efm/<tool>.lua.
---@param root_dir  string
---@param tool_name string
---@param data      table
---@return boolean
function M.save_efm_tool(root_dir, tool_name, data)
	ensure_dir(dir_path(root_dir) .. "/" .. EFM_DIR)
	local path = efm_tool_path(root_dir, tool_name)
	local existing = load_file(path)
	local merged = deep_merge(existing, data)
	local ok = write_file(path, merged)
	if ok then
		_efm_tool_cache[root_dir .. "/" .. tool_name] = merged
	end
	return ok
end

--- Apply EFM tool overrides for this session only (no disk write).
---@param root_dir  string
---@param tool_name string
---@param data      table
function M.apply_efm_tool_session(root_dir, tool_name, data)
	local key = root_dir .. "/" .. tool_name
	local existing = _efm_tool_cache[key] or load_file(efm_tool_path(root_dir, tool_name))
	_efm_tool_cache[key] = deep_merge(existing, data)
end

--- Invalidate cached EFM tool overrides.
---@param root_dir  string
---@param tool_name string
function M.invalidate_efm_tool(root_dir, tool_name)
	_efm_tool_cache[root_dir .. "/" .. tool_name] = nil
end

-- ── Public: invalidate all caches for a root ──────────────────────────────────

--- Invalidate all caches for `root_dir` (config + all servers + all filetypes).
---@param root_dir string
function M.invalidate_all(root_dir)
	_config_cache[root_dir] = nil
	for key in pairs(_server_cache) do
		if vim.startswith(key, root_dir .. "/") then
			_server_cache[key] = nil
		end
	end
	for key in pairs(_ft_cache) do
		if vim.startswith(key, root_dir .. "/") then
			_ft_cache[key] = nil
		end
	end
	for key in pairs(_efm_tool_cache) do
		if vim.startswith(key, root_dir .. "/") then
			_efm_tool_cache[key] = nil
		end
	end
end

return M
