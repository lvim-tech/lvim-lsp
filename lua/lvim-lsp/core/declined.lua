-- lvim-lsp: persistence for user-declined server installs.
-- Stores { [ft] = { [server_name] = true } } and saves to stdpath("data").
---@module "lvim-lsp.core.declined"

local state = require("lvim-lsp.state")
local M     = {}

---@return string
local function disk_path()
    return vim.fn.stdpath("data") .. "/lvim-lsp-declined.json"
end

--- Load declined state from disk into state.declined_servers.
function M.load()
    local ok, lines = pcall(vim.fn.readfile, disk_path())
    if not ok or not lines or #lines == 0 then return end
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

---@param ft          string
---@param server_name string
---@return boolean
function M.is_declined(ft, server_name)
    return state.declined_servers[ft] ~= nil
        and state.declined_servers[ft][server_name] == true
end

---@param ft          string
---@param server_name string
function M.decline(ft, server_name)
    state.declined_servers[ft] = state.declined_servers[ft] or {}
    state.declined_servers[ft][server_name] = true
    M.save()
end

---@param ft          string
---@param server_name string
function M.undecline(ft, server_name)
    if not state.declined_servers[ft] then return end
    state.declined_servers[ft][server_name] = nil
    if vim.tbl_isempty(state.declined_servers[ft]) then
        state.declined_servers[ft] = nil
    end
    M.save()
end

--- Returns { ft = { server_name = true } } — a snapshot of all declined entries.
---@return table<string, table<string, boolean>>
function M.get_all()
    return vim.deepcopy(state.declined_servers)
end

return M
