-- lvim-lsp: project-local configuration loader.
-- Searches for a .lvim-lsp.lua file in the project root directory and merges
-- its settings over the global config on a per-buffer basis.
--
-- Supported keys in .lvim-lsp.lua:
--   disable     string[]          Server names to disable for this project
--   auto_format boolean|nil       Override global features.auto_format
--   inlay_hints boolean|nil       Override global features.inlay_hints
--   code_lens   { enabled: bool } Override global code_lens.enabled
--
---@module "lvim-lsp.core.project"

local M = {}

--- root_dir → loaded config table (empty table = file absent or invalid)
---@type table<string, table>
local cache = {}

local CONFIG_FILE = ".lvim-lsp.lua"

--- Load (and cache) the project config for `root_dir`.
--- Returns an empty table when no config file is found.
---@param root_dir string
---@return table
function M.load(root_dir)
    if cache[root_dir] ~= nil then
        return cache[root_dir]
    end
    local path = root_dir .. "/" .. CONFIG_FILE
    local ok, cfg = pcall(dofile, path)
    cache[root_dir] = (ok and type(cfg) == "table") and cfg or {}
    return cache[root_dir]
end

--- Drop the cached config for `root_dir` so it is re-read on next access.
---@param root_dir string
function M.invalidate(root_dir)
    cache[root_dir] = nil
end

--- Returns true when `server_name` is listed in the project's `disable` array.
---@param root_dir    string
---@param server_name string
---@return boolean
function M.is_server_disabled(root_dir, server_name)
    local cfg = M.load(root_dir)
    return type(cfg.disable) == "table"
        and vim.tbl_contains(cfg.disable, server_name)
end

--- Returns the effective value of a feature flag for a project root.
--- Falls back to `global_value` when the project config does not override it.
---@param root_dir     string
---@param key          string   Top-level key in the project config (e.g. "auto_format")
---@param global_value any      Value from state.config.features or state.config.code_lens
---@return any
function M.get_feature(root_dir, key, global_value)
    local cfg = M.load(root_dir)
    if cfg[key] ~= nil then
        return cfg[key]
    end
    return global_value
end

--- Returns the path where a new project config should be created for `root_dir`.
---@param root_dir string
---@return string
function M.config_path(root_dir)
    return root_dir .. "/" .. CONFIG_FILE
end

return M
