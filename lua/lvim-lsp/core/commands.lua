-- lvim-lsp: user-facing commands, keymaps, and interactive menus.
-- Registers Neovim user-commands that wrap vim.lsp.buf.* calls and provides
-- interactive menus (via vim.ui.select) for toggling, restarting, and
-- inspecting LSP servers both globally and per-buffer.
--
---@module "lvim-lsp.core.commands"

local state       = require("lvim-lsp.state")
local lsp_manager = require("lvim-lsp.core.manager")
local bootstrap   = require("lvim-lsp.core.bootstrap")

-- ── lvim_toggle_lsp_server ────────────────────────────────────────────────────

local function toggle_servers_globally()
    local servers_info    = {}
    local running_servers = {}
    local disabled_servers = state.disabled_servers or {}

    for _, client in ipairs(vim.lsp.get_clients()) do
        running_servers[client.name] = client.id
    end

    if state.file_types then
        for server_name, _ in pairs(state.file_types) do
            servers_info[server_name] = {
                name   = server_name,
                status = disabled_servers[server_name] and "Disabled"
                    or running_servers[server_name] and "Running"
                    or "Not Running",
            }
        end
    end

    local has_efm = #state.efm_filetypes > 0
    if has_efm or running_servers["efm"] or disabled_servers["efm"] then
        servers_info["efm"] = {
            name   = "efm",
            status = disabled_servers["efm"] and "Disabled"
                or running_servers["efm"] and "Running"
                or "Not Running",
        }
    end

    local has_not_running, has_disabled = false, false
    for _, info in pairs(servers_info) do
        if info.status == "Not Running" then has_not_running = true end
        if info.status == "Disabled"    then has_disabled    = true end
    end

    local menu_items = {}
    local menu_map   = {}

    if has_not_running then
        table.insert(menu_items, { text = "Start All Not Running Servers", action = "start_not_running" })
        menu_map["Start All Not Running Servers"] = menu_items[#menu_items]
    end
    if next(running_servers) ~= nil then
        table.insert(menu_items, { text = "Disable All Running Servers", action = "disable_all" })
        menu_map["Disable All Running Servers"] = menu_items[#menu_items]
    end
    if has_disabled then
        table.insert(menu_items, { text = "Enable All Disabled Servers", action = "enable_all" })
        menu_map["Enable All Disabled Servers"] = menu_items[#menu_items]
    end

    for _, info in pairs(servers_info) do
        local item = {
            text   = string.format("%s (%s)", info.name, info.status),
            server = info.name,
            status = info.status,
        }
        table.insert(menu_items, item)
        menu_map[item.text] = item
    end

    table.sort(menu_items, function(a, b)
        if a.action and not b.action then return true  end
        if b.action and not a.action then return false end
        if a.action and b.action then
            local order = { start_not_running = 1, disable_all = 2, enable_all = 3 }
            return (order[a.action] or 999) < (order[b.action] or 999)
        end
        local status_order = { Running = 1, ["Not Running"] = 2, Disabled = 3 }
        if a.status ~= b.status then
            return (status_order[a.status] or 999) < (status_order[b.status] or 999)
        end
        return (a.server or "") < (b.server or "")
    end)

    table.insert(menu_items, { text = "Cancel", action = "cancel" })
    menu_map["Cancel"] = menu_items[#menu_items]

    local display_items = {}
    for _, item in ipairs(menu_items) do
        table.insert(display_items, item.text)
    end

    vim.ui.select(display_items, { prompt = "LSP Servers Management" }, function(choice)
        if not choice or choice == "Cancel" then return end
        local selected = menu_map[choice]
        if not selected then return end

        if selected.action == "start_not_running" then
            local count = 0
            for server_name, info in pairs(servers_info) do
                if info.status == "Not Running" then
                    if lsp_manager.start_language_server(server_name, true) then
                        count = count + 1
                    end
                end
            end
            vim.notify("Started " .. count .. " LSP server(s)", vim.log.levels.INFO)
        elseif selected.action == "disable_all" then
            local count = 0
            for server_name in pairs(running_servers) do
                lsp_manager.disable_lsp_server_globally(server_name)
                count = count + 1
            end
            vim.notify("Disabled " .. count .. " LSP server(s)", vim.log.levels.INFO)
        elseif selected.action == "enable_all" then
            local count = 0
            for server_name, _ in pairs(disabled_servers) do
                lsp_manager.enable_lsp_server_globally(server_name)
                lsp_manager.start_language_server(server_name, true)
                count = count + 1
            end
            vim.notify("Enabled and started " .. count .. " LSP server(s)", vim.log.levels.INFO)
        elseif selected.action == "cancel" then
            return
        elseif selected.server then
            local server_name = selected.server
            local status      = selected.status
            if status == "Running" then
                lsp_manager.disable_lsp_server_globally(server_name)
                vim.notify("Disabled: " .. server_name, vim.log.levels.INFO)
            elseif status == "Disabled" then
                lsp_manager.enable_lsp_server_globally(server_name)
                local cid = lsp_manager.start_language_server(server_name, true)
                if cid then
                    vim.notify("Enabled and started: " .. server_name, vim.log.levels.INFO)
                else
                    vim.notify("Enabled, but failed to start: " .. server_name, vim.log.levels.WARN)
                end
            elseif status == "Not Running" then
                local cid = lsp_manager.start_language_server(server_name, true)
                if cid then
                    vim.notify("Started: " .. server_name, vim.log.levels.INFO)
                else
                    vim.notify("Failed to start: " .. server_name, vim.log.levels.ERROR)
                end
            end
        end
    end)
end

-- ── toggle_servers_for_buffer ─────────────────────────────────────────────────

local function toggle_servers_for_buffer(bufnr)
    local current_bufnr = bufnr or vim.api.nvim_get_current_buf()
    local ft            = vim.bo[current_bufnr].filetype
    if not ft or ft == "" then
        vim.notify("Current buffer has no filetype", vim.log.levels.WARN)
        return
    end

    local compatible_servers = lsp_manager.get_compatible_lsp_for_ft(ft)
    if #compatible_servers == 0 then
        vim.notify("No compatible LSP servers for filetype: " .. ft, vim.log.levels.WARN)
        return
    end

    local servers_status = {}
    for _, server_name in ipairs(compatible_servers) do
        local status    = "unknown"
        local client_id = nil

        if state.disabled_servers[server_name] then
            status = "globally_disabled"
        elseif state.disabled_for_buffer[current_bufnr]
            and state.disabled_for_buffer[current_bufnr][server_name]
        then
            status = "buffer_disabled"
        else
            for _, client in ipairs(vim.lsp.get_clients({ bufnr = current_bufnr })) do
                if client.name == server_name then
                    status    = "attached"
                    client_id = client.id
                    break
                end
            end
            if status == "unknown" then
                for _, client in ipairs(vim.lsp.get_clients()) do
                    if client.name == server_name then
                        status    = "running"
                        client_id = client.id
                        break
                    end
                end
            end
            if status == "unknown" then
                status = "not_started"
            end
        end

        servers_status[server_name] = { name = server_name, status = status, client_id = client_id }
    end

    local menu_items     = {}
    local has_detachable = false
    local has_attachable = false

    for _, info in pairs(servers_status) do
        if info.status == "attached" then
            has_detachable = true
        elseif info.status == "running" or info.status == "not_started" or info.status == "buffer_disabled" then
            has_attachable = true
        end
    end

    if has_attachable then
        table.insert(menu_items, { text = "Attach All Compatible Servers", action_type = "attach_all" })
    end
    if has_detachable then
        table.insert(menu_items, { text = "Detach All Servers", action_type = "detach_all" })
    end

    for _, info in pairs(servers_status) do
        local text, action_type
        if info.status == "attached" then
            text        = "Detach: " .. info.name
            action_type = "detach"
        elseif info.status == "buffer_disabled" then
            text        = "Enable for Buffer: " .. info.name
            action_type = "enable_buffer"
        elseif info.status == "running" then
            text        = "Attach: " .. info.name
            action_type = "attach"
        elseif info.status == "not_started" then
            text        = "Start & Attach: " .. info.name
            action_type = "start_attach"
        elseif info.status == "globally_disabled" then
            text        = "Globally Disabled: " .. info.name
            action_type = "enable_global"
        end
        table.insert(menu_items, {
            text        = text,
            server      = info.name,
            status      = info.status,
            action_type = action_type,
            client_id   = info.client_id,
        })
    end

    table.sort(menu_items, function(a, b)
        local order = { detach = 1, enable_buffer = 2, attach = 3, start_attach = 4, enable_global = 5 }
        local oa = order[a.action_type] or 999
        local ob = order[b.action_type] or 999
        if oa ~= ob then return oa < ob end
        return (a.server or "") < (b.server or "")
    end)

    table.insert(menu_items, { text = "Cancel", action_type = "cancel" })

    local display_items = {}
    for _, item in ipairs(menu_items) do
        table.insert(display_items, item.text)
    end

    vim.ui.select(display_items, { prompt = "LSP for Buffer (" .. ft .. ")" }, function(choice)
        if not choice or choice == "Cancel" then return end
        local selected
        for _, item in ipairs(menu_items) do
            if item.text == choice then
                selected = item
                break
            end
        end
        if not selected then return end

        local action_type = selected.action_type
        local server_name = selected.server

        if action_type == "attach_all" then
            for _, info in pairs(servers_status) do
                if info.status == "buffer_disabled" then
                    lsp_manager.enable_lsp_server_for_buffer(info.name, current_bufnr)
                end
                if info.status == "running" then
                    for _, client in ipairs(vim.lsp.get_clients()) do
                        if client.name == info.name then
                            pcall(vim.lsp.buf_attach_client, current_bufnr, client.id)
                            break
                        end
                    end
                elseif info.status == "not_started" then
                    local cid = lsp_manager.start_language_server(info.name, true)
                    if cid then
                        pcall(vim.lsp.buf_attach_client, current_bufnr, cid)
                    end
                end
            end
            vim.notify("Attached all compatible LSP servers to buffer", vim.log.levels.INFO)
        elseif action_type == "detach_all" then
            for _, info in pairs(servers_status) do
                if info.status == "attached" then
                    lsp_manager.disable_lsp_server_for_buffer(info.name, current_bufnr)
                end
            end
            vim.notify("Detached all LSP servers from buffer", vim.log.levels.INFO)
        elseif action_type == "cancel" then
            return
        elseif action_type == "detach" then
            lsp_manager.disable_lsp_server_for_buffer(server_name, current_bufnr)
            vim.notify("Detached " .. server_name .. " from buffer", vim.log.levels.INFO)
        elseif action_type == "enable_buffer" then
            lsp_manager.enable_lsp_server_for_buffer(server_name, current_bufnr)
            vim.notify("Enabled " .. server_name .. " for buffer", vim.log.levels.INFO)
        elseif action_type == "attach" then
            for _, client in ipairs(vim.lsp.get_clients()) do
                if client.name == server_name then
                    local success = pcall(vim.lsp.buf_attach_client, current_bufnr, client.id)
                    if success then
                        vim.notify("Attached " .. server_name .. " to buffer", vim.log.levels.INFO)
                    else
                        vim.notify("Failed to attach " .. server_name, vim.log.levels.ERROR)
                    end
                    break
                end
            end
        elseif action_type == "start_attach" then
            local cid = lsp_manager.start_language_server(server_name, true)
            if cid then
                local success = pcall(vim.lsp.buf_attach_client, current_bufnr, cid)
                if success then
                    vim.notify("Started " .. server_name .. " and attached to buffer", vim.log.levels.INFO)
                else
                    vim.notify("Started " .. server_name .. " but failed to attach", vim.log.levels.WARN)
                end
            else
                vim.notify("Failed to start " .. server_name, vim.log.levels.ERROR)
            end
        elseif action_type == "enable_global" then
            lsp_manager.enable_lsp_server_globally(server_name)
            local cid = lsp_manager.start_language_server(server_name, true)
            if cid then
                pcall(vim.lsp.buf_attach_client, current_bufnr, cid)
                vim.notify("Enabled and attached " .. server_name, vim.log.levels.INFO)
            else
                vim.notify("Enabled " .. server_name .. " but failed to start", vim.log.levels.WARN)
            end
        end
    end)
end

-- ── lsp_restart ───────────────────────────────────────────────────────────────

local function lsp_restart()
    local running_clients = vim.lsp.get_clients()
    if #running_clients == 0 then
        vim.notify("No LSP servers are running.", vim.log.levels.INFO)
        return
    end

    local running_servers = {}
    for _, client in ipairs(running_clients) do
        running_servers[client.name] = true
    end

    local menu_items = {}
    local menu_map   = {}
    for server_name in pairs(running_servers) do
        local text = string.format("Restart: %s", server_name)
        local item = { text = text, server = server_name, action = "restart" }
        table.insert(menu_items, item)
        menu_map[text] = item
    end

    table.sort(menu_items, function(a, b) return a.server < b.server end)

    local cancel_item = { text = "Cancel", action = "cancel" }
    table.insert(menu_items, cancel_item)
    menu_map["Cancel"] = cancel_item

    local display_items = {}
    for _, item in ipairs(menu_items) do
        table.insert(display_items, item.text)
    end

    vim.ui.select(display_items, { prompt = "Restart LSP Server..." }, function(choice)
        if not choice or choice == "Cancel" then return end
        local selected = menu_map[choice]
        if not selected or not selected.server then return end

        local server_name = selected.server
        local attached_bufs = {}
        for _, client in ipairs(running_clients) do
            if client.name == server_name then
                for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                    for _, c in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
                        if c.id == client.id then
                            table.insert(attached_bufs, bufnr)
                        end
                    end
                end
                client:stop()
            end
        end

        vim.defer_fn(function()
            local ok, new_cid = pcall(lsp_manager.start_language_server, server_name, true)
            if ok and new_cid then
                for _, bufnr in ipairs(attached_bufs) do
                    pcall(vim.lsp.buf_attach_client, bufnr, new_cid)
                end
                vim.notify("Restarted and re-attached: " .. server_name, vim.log.levels.INFO)
            else
                vim.notify("Restarted: " .. server_name, vim.log.levels.INFO)
            end
        end, 500)
    end)
end

-- ── lsp_info ──────────────────────────────────────────────────────────────────
-- Delegates to lvim-lsp.ui.info — all rendering logic lives there.

local function lsp_info()
    return require("lvim-lsp.ui.info").show()
end


-- ── Registration ──────────────────────────────────────────────────────────────

local M = {}

--- Invisible border (padding without a visible frame).
local _border = {
    { " ", "FloatBorder" }, { " ", "FloatBorder" }, { " ", "FloatBorder" }, { " ", "FloatBorder" },
    { " ", "FloatBorder" }, { " ", "FloatBorder" }, { " ", "FloatBorder" }, { " ", "FloatBorder" },
}

--- Register all user commands.  Called once from bootstrap.
function M.setup()
    local diag_cfg = state.config.diagnostics

    -- ── helpers ───────────────────────────────────────────────────────────────

    local function require_method(method, fn)
        return function(opts)
            local clients = vim.lsp.get_clients({ bufnr = 0, method = method })
            if #clients == 0 then
                vim.notify("No LSP client supporting " .. method .. " found", vim.log.levels.WARN)
                return
            end
            fn(opts)
        end
    end

    local function require_client(fn)
        return function(opts)
            if #vim.lsp.get_clients({ bufnr = 0 }) == 0 then
                vim.notify("No active LSP client found", vim.log.levels.WARN)
                return
            end
            fn(opts)
        end
    end

    -- ── subcommand dispatch table ─────────────────────────────────────────────

    local subcommands = {
        hover                   = require_method("textDocument/hover",                    function() vim.lsp.buf.hover({ border = _border }) end),
        rename                  = require_method("textDocument/rename",                   function() vim.lsp.buf.rename(nil, { border = _border }) end),
        format                  = require_method("textDocument/formatting",               function() vim.lsp.buf.format({ async = false }) end),
        code_action             = require_method("textDocument/codeAction",               function() vim.lsp.buf.code_action({ border = _border }) end),
        definition              = require_method("textDocument/definition",               function() vim.lsp.buf.definition() end),
        type_definition         = require_method("textDocument/typeDefinition",           function() vim.lsp.buf.type_definition() end),
        declaration             = require_method("textDocument/declaration",              function() vim.lsp.buf.declaration() end),
        references              = require_method("textDocument/references",               function() vim.lsp.buf.references(nil, { border = _border }) end),
        implementation          = require_method("textDocument/implementation",           function() vim.lsp.buf.implementation() end),
        signature_help          = require_method("textDocument/signatureHelp",            function() vim.lsp.buf.signature_help({ border = _border }) end),
        document_symbol         = require_method("textDocument/documentSymbol",           function() vim.lsp.buf.document_symbol() end),
        workspace_symbol        = require_method("workspace/symbol",                      function() vim.lsp.buf.workspace_symbol() end),
        document_highlight      = require_method("textDocument/documentHighlight",        function() vim.lsp.buf.document_highlight() end),
        clear_references        = require_method("textDocument/documentHighlight",        function() vim.lsp.buf.clear_references() end),
        incoming_calls          = require_method("callHierarchy/incomingCalls",           function() vim.lsp.buf.incoming_calls() end),
        outgoing_calls          = require_method("callHierarchy/outgoingCalls",           function() vim.lsp.buf.outgoing_calls() end),
        add_workspace_folder    = require_method("workspace/didChangeWorkspaceFolders",   function() vim.lsp.buf.add_workspace_folder() end),
        remove_workspace_folder = require_method("workspace/didChangeWorkspaceFolders",   function() vim.lsp.buf.remove_workspace_folder() end),
        list_workspace_folders  = function() print(vim.inspect(vim.lsp.buf.list_workspace_folders())) end,
        range_format            = require_method("textDocument/rangeFormatting",          function(opts)
            vim.lsp.buf.format({
                range    = { ["start"] = { opts.line1, 0 }, ["end"] = { opts.line2, 0 } },
                async    = false,
            })
        end),
        diagnostic_current = require_client(function()
            if diag_cfg.show_line then diag_cfg.show_line() else vim.diagnostic.open_float() end
        end),
        diagnostic_next    = require_client(function()
            if diag_cfg.goto_next then diag_cfg.goto_next() else vim.diagnostic.goto_next() end
        end),
        diagnostic_prev    = require_client(function()
            if diag_cfg.goto_prev then diag_cfg.goto_prev() else vim.diagnostic.goto_prev() end
        end),
        toggle_servers        = toggle_servers_globally,
        toggle_servers_buffer = function(opts) toggle_servers_for_buffer(tonumber(opts.args)) end,
        restart               = lsp_restart,
        info                  = lsp_info,
        reattach              = function() bootstrap.attach_lsp_to_buffer(vim.api.nvim_get_current_buf()) end,
        project               = function()
            local proj = require("lvim-lsp.core.project")
            -- Determine root_dir from the current buffer's LSP clients, or cwd
            local root = vim.loop.cwd()
            for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
                if client.config and client.config.root_dir then
                    root = client.config.root_dir
                    break
                end
            end
            local path = proj.config_path(root)
            local exists = vim.fn.filereadable(path) == 1
            if not exists then
                -- Write a documented template
                local template = {
                    "-- lvim-lsp project configuration",
                    "-- Place this file in your project root and restart Neovim (or :LvimLsp reattach).",
                    "--",
                    "-- disable     = { \"eslint\", \"tsserver\" },  -- servers to skip for this project",
                    "-- auto_format = false,                         -- override global auto_format",
                    "-- inlay_hints = true,                          -- override global inlay_hints",
                    "-- code_lens   = { enabled = true },            -- override global code_lens",
                    "",
                    "return {",
                    "}",
                }
                vim.fn.writefile(template, path)
            end
            -- Invalidate cache so changes take effect immediately on next attach
            proj.invalidate(root)
            vim.cmd("edit " .. vim.fn.fnameescape(path))
        end,
        declined              = function()
            local declined_mod = require("lvim-lsp.core.declined")
            local all = declined_mod.get_all()
            -- Flatten to "server_name [ft]" display items
            local items = {}
            local item_map = {}
            for ft, servers in pairs(all) do
                for server_name, _ in pairs(servers) do
                    local text = server_name .. " [" .. ft .. "]"
                    table.insert(items, text)
                    item_map[text] = { ft = ft, server = server_name }
                end
            end
            if #items == 0 then
                vim.notify("No declined LSP servers.", vim.log.levels.INFO)
                return
            end
            table.sort(items)
            local initial = {}
            for _, text in ipairs(items) do initial[text] = true end
            require("lvim-utils.ui").multiselect({
                title    = " Declined LSP Servers",
                subtitle = "Space = toggle  ·  Enter = re-enable checked  ·  q = cancel",
                items    = items,
                initial_selected = initial,
                callback = function(confirmed, selected)
                    if not confirmed then return end
                    local count = 0
                    for _, text in ipairs(items) do
                        if selected and selected[text] then
                            local entry = item_map[text]
                            declined_mod.undecline(entry.ft, entry.server)
                            count = count + 1
                        end
                    end
                    if count > 0 then
                        vim.notify(
                            string.format("Re-enabled %d server(s). Open a file to trigger install.", count),
                            vim.log.levels.INFO
                        )
                    end
                end,
            })
        end,
    }

    if state.config.dap_local_fn then
        subcommands.dap = function() state.config.dap_local_fn() end
    end

    local subcommand_names = vim.tbl_keys(subcommands)
    table.sort(subcommand_names)

    -- ── single entry-point command ────────────────────────────────────────────

    vim.api.nvim_create_user_command("LvimLsp", function(opts)
        local sub = opts.fargs[1]
        local fn  = subcommands[sub]
        if not fn then
            vim.notify("LvimLsp: unknown subcommand '" .. tostring(sub) .. "'", vim.log.levels.ERROR)
            return
        end
        fn(opts)
    end, {
        nargs    = "+",
        range    = true,
        complete = function(arg_lead, cmd_line, _)
            local parts = vim.split(cmd_line, "%s+")
            if #parts <= 2 then
                return vim.tbl_filter(function(name)
                    return name:find(arg_lead, 1, true) == 1
                end, subcommand_names)
            end
            return {}
        end,
        desc = "LvimLsp — unified LSP interface (:LvimLsp <subcommand>)",
    })
end

return M
