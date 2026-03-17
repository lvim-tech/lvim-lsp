-- lvim-lsp: install-prompt UI using lvim-utils multiselect.
-- Batches all missing tools for a filetype into one popup.
-- Items are the actual tool names (lua-language-server, stylua, …).
-- Pressing Enter installs the checked tools; servers whose tools are all
-- unchecked are declined.  Pressing q/Esc skips without persisting anything.
---@module "lvim-lsp.ui.prompt"

local M = {}

--- ft → { server_name → mod }
---@type table<string, table<string, table>>
local pending   = {}
local scheduled = false

--- ft → { server_name → expiry_ms }  — cooldown after Esc/q (vim.uv.now()-based)
---@type table<string, table<string, integer>>
local snoozed = {}

--- How long (ms) to suppress re-prompting after Esc/q.
local SNOOZE_MS = 5 * 60 * 1000  -- 5 minutes

--- Queue a server for the next prompt cycle.
--- Silently ignores servers still within their post-Esc cooldown.
---@param ft          string
---@param server_name string
---@param mod         table  Full server config module table (dependencies = missing list)
function M.add_pending(ft, server_name, mod)
    if snoozed[ft] and snoozed[ft][server_name]
        and vim.uv.now() < snoozed[ft][server_name]
    then
        return
    end
    pending[ft] = pending[ft] or {}
    pending[ft][server_name] = mod
    if not scheduled then
        scheduled = true
        vim.defer_fn(function()
            scheduled = false
            M.flush()
        end, 300)
    end
end

--- Open one multiselect popup per pending filetype.
--- Items are the individual tool names, not server names.
function M.flush()
    if vim.tbl_isempty(pending) then return end

    local fts = vim.tbl_keys(pending)
    table.sort(fts)

    for _, ft in ipairs(fts) do
        local servers = pending[ft]
        pending[ft]   = nil

        local server_names = vim.tbl_keys(servers)
        if #server_names == 0 then goto continue end
        table.sort(server_names)

        -- Collect unique tool names across all servers, preserving insertion order
        local dep_items    = {}
        local dep_seen     = {}

        for _, sname in ipairs(server_names) do
            for _, dep in ipairs(servers[sname].dependencies or {}) do
                if not dep_seen[dep] then
                    dep_seen[dep] = true
                    table.insert(dep_items, dep)
                end
            end
        end

        table.sort(dep_items)

        if #dep_items == 0 then goto continue end

        local initial = {}
        for _, dep in ipairs(dep_items) do initial[dep] = true end

        require("lvim-utils.ui").multiselect({
            title    = " Install LSP tools for " .. ft,
            subtitle = "Space = toggle  ·  Enter = install checked  ·  q = skip",
            items    = dep_items,
            initial_selected = initial,
            callback = function(confirmed, selected)
                if not confirmed then
                    -- q / Esc: cooldown — suppress re-prompt for SNOOZE_MS
                    local expiry = vim.uv.now() + SNOOZE_MS
                    snoozed[ft] = snoozed[ft] or {}
                    for _, sname in ipairs(server_names) do
                        snoozed[ft][sname] = expiry
                    end
                    return
                end

                local declined = require("lvim-lsp.core.declined")
                local manager  = require("lvim-lsp.core.manager")

                -- Collect the tools the user actually wants installed
                local to_install = {}
                for _, dep in ipairs(dep_items) do
                    if selected and selected[dep] then
                        table.insert(to_install, dep)
                    end
                end

                -- A server is startable if at least one of its tools was checked.
                -- If none were checked the user is effectively declining it.
                local servers_to_start = {}
                for _, sname in ipairs(server_names) do
                    local mod = servers[sname]
                    local any_selected = false
                    for _, dep in ipairs(mod.dependencies or {}) do
                        if selected and selected[dep] then
                            any_selected = true
                            break
                        end
                    end
                    if any_selected then
                        table.insert(servers_to_start, sname)
                    else
                        declined.decline(ft, sname)
                    end
                end

                if #to_install == 0 then return end

                require("lvim-lsp.ui.installer").ensure_mason_tools(
                    to_install,
                    function()
                        -- Register EFM/DAP configs immediately so they are ready when
                        -- set_installation_status(false) triggers ensure_lsp_for_buffer.
                        -- Do NOT call _start_server_for_buffer directly here — the binary
                        -- may not be accessible yet (executable() caching / timing).
                        -- ensure_lsp_for_buffer will re-check is_missing and start only
                        -- when the binary is confirmed present.
                        for _, sname in ipairs(servers_to_start) do
                            local mod = servers[sname]
                            if mod.efm then
                                manager.setup_efm(mod.efm.filetypes, mod.efm.tools)
                            end
                            if mod.dap then
                                require("lvim-lsp.core.dap").setup(mod.dap)
                            end
                        end
                    end
                )
            end,
        })
        ::continue::
    end
end

return M
