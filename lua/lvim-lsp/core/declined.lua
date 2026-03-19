-- lvim-lsp: persistence for user-declined tool installs.
-- Stores { [tool_name] = true } and saves to stdpath("data").
---@module "lvim-lsp.core.declined"

local state = require("lvim-lsp.state")
local M = {}

---@return string
local function disk_path()
	return vim.fn.stdpath("data") .. "/lvim-lsp-declined.json"
end

--- Load declined state from disk into state.declined_servers.
function M.load()
	local ok, lines = pcall(vim.fn.readfile, disk_path())
	if not ok or not lines or #lines == 0 then
		return
	end
	local json_ok, decoded = pcall(vim.json.decode, table.concat(lines, ""))
	if json_ok and type(decoded) == "table" then
		state.declined_servers = decoded
	end
end

--- Persist state.declined_servers to disk.
function M.save()
	local ok, encoded = pcall(vim.json.encode, state.declined_servers)
	if ok then
		pcall(vim.fn.writefile, { encoded }, disk_path())
	end
end

---@param tool_name string
---@return boolean
function M.is_declined(tool_name)
	return state.declined_servers[tool_name] == true
end

---@param tool_name string
function M.decline(tool_name)
	state.declined_servers[tool_name] = true
	M.save()
end

---@param tool_name string
function M.undecline(tool_name)
	state.declined_servers[tool_name] = nil
	M.save()
end

--- Returns { tool_name = true } — a snapshot of all declined entries.
---@return table<string, boolean>
function M.get_all()
	return vim.deepcopy(state.declined_servers)
end

return M
