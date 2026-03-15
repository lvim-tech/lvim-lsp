-- lvim-lsp: low-level LSP lifecycle manager.
-- Responsible for starting, attaching, detaching, enabling, and disabling LSP
-- clients on a per-buffer and per-project-root basis.  Also manages the EFM
-- language server aggregation and handles cleanup of stale servers after a
-- working-directory change.
--
---@module "lvim-lsp.manager"
---@diagnostic disable: undefined-doc-name, undefined-field

local uv    = vim.loop
local state = require("lvim-lsp.state")

local M = {}

-- ── Private helpers ───────────────────────────────────────────────────────────

--- Returns a function that, given a starting path, walks up the directory tree
--- looking for any of the provided `markers` (file or directory names).
--- Returns the first ancestor directory that contains a marker, or nil.
---@param ... string  Marker file/directory names (e.g. ".git", "package.json")
---@return fun(startpath: string): string|nil
local function root_pattern(...)
    local markers = { ... }
    return function(startpath)
        if not startpath or #startpath == 0 then
            return nil
        end
        local path = uv.fs_realpath(startpath) or startpath
        local stat = uv.fs_stat(path)
        if stat and stat.type == "file" then
            path = vim.fn.fnamemodify(path, ":h")
        end
        while path and #path > 0 do
            for _, marker in ipairs(markers) do
                if uv.fs_stat(path .. "/" .. marker) then
                    return path
                end
            end
            local parent = vim.fn.fnamemodify(path, ":h")
            if parent == path then
                break
            end
            path = parent
        end
        return nil
    end
end

--- Returns true when `bufnr` is a valid buffer backed by a file on disk.
---@param bufnr integer
---@return boolean
local function is_real_file_buffer(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return false
    end
    local name = vim.api.nvim_buf_get_name(bufnr)
    return name ~= nil and name ~= ""
end

--- Returns true when `client_id` is currently attached to `bufnr`.
---@param client_id integer
---@param bufnr     integer|nil
---@return boolean
local function is_client_attached_to_buffer(client_id, bufnr)
    if not client_id then
        return false
    end
    if not bufnr or bufnr == 0 then
        bufnr = vim.api.nvim_get_current_buf()
    end
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return false
    end
    local ok, clients = pcall(vim.lsp.get_clients, { bufnr = bufnr })
    if not ok or type(clients) ~= "table" then
        return false
    end
    for _, c in ipairs(clients) do
        if c and c.id == client_id then
            return true
        end
    end
    return false
end

-- ── Public API ─────────────────────────────────────────────────────────────────

--- Returns true when `server_name` has been disabled globally.
---@param server_name string
---@return boolean
M.is_server_disabled_globally = function(server_name)
    return state.disabled_servers[server_name] == true
end

--- Returns true when `server_name` has been disabled for `bufnr`.
---@param server_name string
---@param bufnr       integer
---@return boolean
M.is_server_disabled_for_buffer = function(server_name, bufnr)
    return state.disabled_for_buffer[bufnr] ~= nil
        and state.disabled_for_buffer[bufnr][server_name] == true
end

--- Returns true when `server_name` supports filetype `ft`.
---@param server_name string
---@param ft          string
---@return boolean
M.is_lsp_compatible_with_ft = function(server_name, ft)
    if not ft or ft == "" then
        return false
    end
    if server_name == "efm" then
        if state.efm_configs[ft] then
            return true
        end
        return vim.tbl_contains(state.efm_filetypes, ft)
    end
    if not state.file_types[server_name] then
        return false
    end
    return vim.tbl_contains(state.file_types[server_name], ft)
end

--- Returns all server names (including EFM when applicable) that declare
--- support for filetype `ft`.
---@param ft string
---@return string[]
M.get_compatible_lsp_for_ft = function(ft)
    if not ft or ft == "" then
        return {}
    end
    local result = {}
    for server_name, filetypes in pairs(state.file_types) do
        if vim.tbl_contains(filetypes, ft) then
            table.insert(result, server_name)
        end
    end
    if vim.tbl_contains(state.efm_filetypes, ft) or state.efm_configs[ft] then
        table.insert(result, "efm")
    end
    return result
end

--- Attaches (or starts) `server_name` for buffer `bufnr`.
--- Resolution order:
---   1. If a client for the same root_dir already exists, reuse it.
---   2. Otherwise load the server config via state.config.server_config_dirs,
---      resolve the project root, and start a new client.
---@param server_name string
---@param bufnr       integer
---@return integer|nil  Client id on success
M.ensure_lsp_for_buffer = function(server_name, bufnr)
    if not is_real_file_buffer(bufnr) then
        return nil
    end
    if M.is_server_disabled_globally(server_name) or M.is_server_disabled_for_buffer(server_name, bufnr) then
        return nil
    end
    local ft = vim.bo[bufnr].filetype
    if not M.is_lsp_compatible_with_ft(server_name, ft) then
        return nil
    end

    -- Load server config — search dirs in order, prefer first match
    local ok, mod
    for _, dir in ipairs(state.config.server_config_dirs) do
        ok, mod = pcall(require, dir .. "." .. server_name)
        if ok and type(mod) == "table" and mod.config then
            break
        end
        ok, mod = false, nil
    end
    if not ok or not mod or not mod.config then
        return nil
    end

    local fname    = vim.api.nvim_buf_get_name(bufnr)
    local patterns = mod.root_patterns or { ".git" }
    local finder   = root_pattern(unpack(patterns))
    local root_dir = finder(fname) or vim.loop.cwd()

    state.clients_by_root[server_name] = state.clients_by_root[server_name] or {}
    local client_id = state.clients_by_root[server_name][root_dir]

    if client_id then
        local client = vim.lsp.get_client_by_id(client_id)
        if client then
            if not is_client_attached_to_buffer(client_id, bufnr) then
                vim.lsp.buf_attach_client(bufnr, client_id)
                if type(mod.config) == "table" and type(mod.config.on_attach) == "function" then
                    pcall(mod.config.on_attach, client, bufnr)
                end
            end
            return client_id
        end
    end

    local config = (type(mod.config) == "function") and mod.config() or vim.deepcopy(mod.config)
    if not config then
        return nil
    end
    config.root_dir = root_dir

    local new_client_id = vim.lsp.start({
        name         = config.name or server_name,
        cmd          = config.cmd,
        root_dir     = config.root_dir,
        settings     = config.settings,
        init_options = config.init_options,
        capabilities = config.capabilities,
        on_attach    = function(client, attached_bufnr)
            if attached_bufnr == bufnr and config.on_attach then
                pcall(config.on_attach, client, attached_bufnr)
            end
        end,
    }, { bufnr = bufnr })

    if new_client_id then
        if state.clients_by_root == nil then
            state.clients_by_root = {}
        end
        if state.clients_by_root[server_name] == nil then
            state.clients_by_root[server_name] = {}
        end
        local key = root_dir ~= nil and root_dir or "default"
        state.clients_by_root[server_name][key] = new_client_id
        return new_client_id
    end
    return nil
end

--- Detaches `client_id` from `bufnr` after clearing document highlights.
---@param bufnr     integer
---@param client_id integer
---@return boolean
M.safe_detach_client = function(bufnr, client_id)
    if not bufnr or bufnr <= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
        return false
    end
    local client = vim.lsp.get_client_by_id(client_id)
    if not client then
        return false
    end
    if is_client_attached_to_buffer(client_id, bufnr) then
        pcall(function() vim.lsp.buf.clear_references() end)
        pcall(vim.lsp.buf_detach_client, bufnr, client_id)
        return true
    end
    return false
end

--- Adds `server_name` to the global disabled list and stops all running instances.
---@param server_name string
---@return boolean
M.disable_lsp_server_globally = function(server_name)
    state.disabled_servers[server_name] = true
    for _, client in ipairs(vim.lsp.get_clients()) do
        if client.name == server_name then
            local attached_buffers = {}
            for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_valid(bufnr) then
                    local ok, buf_clients = pcall(vim.lsp.get_clients, { bufnr = bufnr })
                    if ok and type(buf_clients) == "table" then
                        for _, c in ipairs(buf_clients) do
                            if c and c.id == client.id then
                                attached_buffers[bufnr] = true
                                break
                            end
                        end
                    end
                end
            end
            for bufnr, _ in pairs(attached_buffers) do
                if vim.api.nvim_buf_is_valid(bufnr) then
                    M.safe_detach_client(bufnr, client.id)
                end
            end
            pcall(function()
                if type(client.stop) == "function" then
                    client:stop()
                else
                    local fallback = vim.lsp.get_client_by_id(client.id)
                    if fallback and type(fallback.stop) == "function" then
                        fallback:stop()
                    end
                end
            end)
        end
    end
    return true
end

--- Disables `server_name` for a single buffer and detaches it immediately.
---@param server_name string
---@param bufnr       integer
---@return boolean
M.disable_lsp_server_for_buffer = function(server_name, bufnr)
    if not state.disabled_for_buffer[bufnr] then
        state.disabled_for_buffer[bufnr] = {}
    end
    state.disabled_for_buffer[bufnr][server_name] = true
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
        if client.name == server_name then
            M.safe_detach_client(bufnr, client.id)
            break
        end
    end
    return true
end

--- Re-enables `server_name` globally (removes from the disabled list).
--- Does NOT automatically re-attach; callers trigger that separately.
---@param server_name string
---@return boolean
M.enable_lsp_server_globally = function(server_name)
    state.disabled_servers[server_name] = nil
    return true
end

--- Re-enables `server_name` for `bufnr` and immediately re-attaches it when possible.
---@param server_name string
---@param bufnr       integer
---@return boolean
M.enable_lsp_server_for_buffer = function(server_name, bufnr)
    if state.disabled_for_buffer[bufnr] then
        state.disabled_for_buffer[bufnr][server_name] = nil
    end
    if M.is_server_disabled_globally(server_name) then
        return false
    end
    local ft = vim.bo[bufnr].filetype
    if ft and ft ~= "" and M.is_lsp_compatible_with_ft(server_name, ft) and is_real_file_buffer(bufnr) then
        local already_attached = false
        for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
            if client.name == server_name then
                already_attached = true
                break
            end
        end
        if not already_attached then
            local client_id
            for _, client in ipairs(vim.lsp.get_clients()) do
                if client.name == server_name then
                    client_id = client.id
                    break
                end
            end
            if client_id then
                pcall(vim.lsp.buf_attach_client, bufnr, client_id)
            else
                M.ensure_lsp_for_buffer(server_name, bufnr)
            end
        end
    end
    return true
end

--- Starts `server_name` by finding a compatible open buffer.
--- When `force` is true, also attaches to every other compatible buffer.
---@param server_name string
---@param force       boolean
---@return integer|nil
M.start_language_server = function(server_name, force)
    if state.installation_in_progress then
        return nil
    end
    if not force and M.is_server_disabled_globally(server_name) then
        return nil
    end

    local function find_compatible_buf()
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if is_real_file_buffer(buf) then
                local buf_ft = vim.bo[buf].filetype
                if buf_ft ~= "" and M.is_lsp_compatible_with_ft(server_name, buf_ft) then
                    return buf, buf_ft
                end
            end
        end
        return nil, nil
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local ft    = vim.bo[bufnr].filetype
    if not is_real_file_buffer(bufnr) or not M.is_lsp_compatible_with_ft(server_name, ft) then
        bufnr, ft = find_compatible_buf()
        if not bufnr or not is_real_file_buffer(bufnr) or not M.is_lsp_compatible_with_ft(server_name, ft) then
            if not force then
                return nil
            end
            bufnr = nil
        end
    end
    if not bufnr or not is_real_file_buffer(bufnr) then
        return nil
    end

    local client_id = M.ensure_lsp_for_buffer(server_name, bufnr)

    if force and client_id then
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if buf ~= bufnr and is_real_file_buffer(buf) then
                local buf_ft = vim.bo[buf].filetype
                if buf_ft ~= "" and M.is_lsp_compatible_with_ft(server_name, buf_ft) then
                    if not M.is_server_disabled_for_buffer(server_name, buf) then
                        vim.lsp.buf_attach_client(buf, client_id)
                    end
                end
            end
        end
    end
    return client_id
end

--- Convenience wrapper: starts `server_name` for the current buffer.
---@param server_name string
---@return integer|nil
M.lsp_enable = function(server_name)
    return M.ensure_lsp_for_buffer(server_name, vim.api.nvim_get_current_buf())
end

--- Stops all LSP clients whose root_dir is outside the current working directory.
--- Called on DirChanged to clean up stale servers from the previous project.
---@return integer  Number of servers scheduled to stop
M.stop_servers_for_old_project = function()
    local current_dir   = vim.fn.getcwd()
    local stopped_count = 0
    for _, client in ipairs(vim.lsp.get_clients()) do
        if client.config and client.config.root_dir then
            local client_root
            if type(client.config.root_dir) == "function" then
                goto continue
            else
                client_root = tostring(client.config.root_dir)
            end
            if client_root ~= current_dir and not vim.startswith(client_root, current_dir) then
                local cid = client.id
                vim.schedule(function()
                    local c = vim.lsp.get_client_by_id(cid)
                    if c and type(c.stop) == "function" then
                        pcall(function() c:stop() end)
                    end
                end)
                stopped_count = stopped_count + 1
            end
        end
        ::continue::
    end
    if stopped_count > 0 then
        vim.schedule(function()
            vim.notify(
                string.format("Stopped %d LSP server(s) from other projects.", stopped_count),
                vim.log.levels.INFO
            )
        end)
    end
    return stopped_count
end

-- ── EFM management ────────────────────────────────────────────────────────────

---@type uv_timer_t|nil
local efm_restart_timer = nil
local efm_restart_delay = 100
---@type boolean
local efm_setup_in_progress = false

--- Merges `tools_config` into `state.efm_configs` for each filetype in
--- `filetypes`, deduplicating by `server_name`, then restarts EFM.
---@param filetypes    string[]
---@param tools_config table[]
M.setup_efm = function(filetypes, tools_config)
    if efm_setup_in_progress then
        vim.schedule(function()
            vim.defer_fn(function()
                M.setup_efm(filetypes, tools_config)
            end, 100)
        end)
        return
    end
    efm_setup_in_progress = true

    for _, ft in ipairs(filetypes) do
        state.efm_configs[ft] = state.efm_configs[ft] or {}
        local existing = {}
        for _, tool in ipairs(state.efm_configs[ft]) do
            if tool.server_name then
                existing[tool.server_name] = true
            end
        end
        for _, tool in ipairs(tools_config) do
            if tool.server_name and not existing[tool.server_name] then
                table.insert(state.efm_configs[ft], tool)
                existing[tool.server_name] = true
            end
        end
    end

    vim.schedule(function()
        if efm_restart_timer then
            efm_restart_timer:stop()
        end
        efm_restart_timer = vim.defer_fn(function()
            local efm_running = false
            for _, client in ipairs(vim.lsp.get_clients()) do
                if client.name == "efm" then
                    efm_running = true
                    pcall(function()
                        if type(client.stop) == "function" then
                            client:stop()
                        else
                            local fallback = vim.lsp.get_client_by_id(client.id)
                            if fallback and type(fallback.stop) == "function" then
                                fallback:stop()
                            end
                        end
                    end)
                    break
                end
            end
            vim.defer_fn(function()
                M.start_language_server("efm", true)
                efm_setup_in_progress = false
            end, efm_running and 200 or 0)
        end, efm_restart_delay)
    end)

    if not vim.defer_fn then
        efm_setup_in_progress = false
    end
end

--- Tracks Mason installation status.
--- Transitioning true → false triggers auto-start of newly-available servers
--- and re-attaches them to all open file buffers.
---@param status boolean
M.set_installation_status = function(status)
    local previous = state.installation_in_progress
    state.installation_in_progress = status

    if status == false and previous == true then
        vim.defer_fn(function()
            local efm_exe = state.config.efm.executable
            local installed = {}
            for server_name, _ in pairs(state.file_types) do
                if
                    vim.fn.executable(server_name) == 1
                    or (server_name == "efm" and vim.fn.executable(efm_exe) == 1)
                then
                    table.insert(installed, server_name)
                end
            end
            for _, server_name in ipairs(installed) do
                vim.schedule(function()
                    M.start_language_server(server_name, true)
                end)
            end
            vim.defer_fn(function()
                for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                    if is_real_file_buffer(bufnr) then
                        local ft = vim.bo[bufnr].filetype
                        if ft and ft ~= "" then
                            local servers = M.get_compatible_lsp_for_ft(ft)
                            for _, server_name in ipairs(servers) do
                                if not M.is_server_disabled_globally(server_name) then
                                    vim.schedule(function()
                                        M.ensure_lsp_for_buffer(server_name, bufnr)
                                    end)
                                end
                            end
                        end
                    end
                end
            end, 500)
        end, 1000)
    end
end

return M
