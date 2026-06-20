-- lvim-lsp: user-facing commands, keymaps, and interactive menus.
-- Registers Neovim user-commands that wrap vim.lsp.buf.* calls and provides
-- interactive menus (via lvim-utils UI) for toggling, restarting, and
-- inspecting LSP servers both globally and per-buffer.
--
---@module "lvim-lsp.core.commands"

local lsp_state = require("lvim-lsp.state")
local ui_info = require("lvim-lsp.ui.info")
local ui_project = require("lvim-lsp.ui.project")
local lsp_ui = require("lvim-lsp.ui")

local state = require("lvim-ls.state")
local lsp_manager = require("lvim-ls.core.manager")
local notify = require("lvim-ls.utils.notify")

-- ── toggle_servers_globally ───────────────────────────────────────────────────

local function toggle_servers_globally()
    local running = {}
    for _, client in ipairs(vim.lsp.get_clients()) do
        running[client.name] = true
    end

    local seen = {}
    if state.file_types then
        for name in pairs(state.file_types) do
            seen[name] = true
        end
    end
    for name in pairs(running) do
        seen[name] = true
    end
    local disabled = state.disabled_servers or {}
    if #state.efm_filetypes > 0 or running["efm"] or disabled["efm"] then
        seen["efm"] = true
    end

    local server_names = vim.tbl_keys(seen)
    table.sort(server_names)

    if #server_names == 0 then
        notify("No LSP servers configured.", vim.log.levels.INFO)
        return
    end

    -- checked = currently running and not disabled
    local initial_selected = {}
    for _, name in ipairs(server_names) do
        if running[name] and not disabled[name] then
            initial_selected[name] = true
        end
    end

    local menus_cfg = (lsp_state.config.menus or {}).toggle_servers or {}
    lsp_ui.get().multiselect({
        title = menus_cfg.title,
        subtitle = menus_cfg.subtitle,
        items = server_names,
        initial_selected = initial_selected,
        callback = function(confirmed, selected)
            if not confirmed then
                return
            end
            for _, name in ipairs(server_names) do
                if selected and selected[name] then
                    lsp_manager.enable_lsp_server_globally(name)
                    lsp_manager.start_language_server(name, true)
                else
                    lsp_manager.disable_lsp_server_globally(name)
                end
            end
        end,
    })
end

-- ── toggle_servers_for_buffer ─────────────────────────────────────────────────

local function toggle_servers_for_buffer(bufnr)
    local current_bufnr = bufnr or vim.api.nvim_get_current_buf()
    local ft = vim.bo[current_bufnr].filetype
    if not ft or ft == "" then
        notify("Current buffer has no filetype", vim.log.levels.WARN)
        return
    end

    local all_compatible = lsp_manager.get_compatible_lsp_for_ft(ft)
    local server_names = {}
    for _, name in ipairs(all_compatible) do
        if not lsp_manager.is_server_disabled_globally(name) then
            table.insert(server_names, name)
        end
    end
    table.sort(server_names)

    if #server_names == 0 then
        notify("No compatible LSP servers for filetype: " .. ft, vim.log.levels.WARN)
        return
    end

    -- checked = currently attached to buffer
    local attached = {}
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = current_bufnr })) do
        attached[client.name] = true
    end

    local initial_selected = {}
    for _, name in ipairs(server_names) do
        if attached[name] then
            initial_selected[name] = true
        end
    end

    local menus_cfg = (lsp_state.config.menus or {}).toggle_servers_buffer or {}
    lsp_ui.get().multiselect({
        title = menus_cfg.title,
        subtitle = ft,
        items = server_names,
        initial_selected = initial_selected,
        callback = function(confirmed, selected)
            if not confirmed then
                return
            end
            for _, name in ipairs(server_names) do
                if selected and selected[name] then
                    lsp_manager.enable_lsp_server_for_buffer(name, current_bufnr)
                else
                    lsp_manager.disable_lsp_server_for_buffer(name, current_bufnr)
                end
            end
        end,
    })
end

-- ── lsp_reattach ──────────────────────────────────────────────────────────────

local function lsp_reattach()
    local current_bufnr = vim.api.nvim_get_current_buf()
    local ft = vim.bo[current_bufnr].filetype
    if not ft or ft == "" then
        notify("Current buffer has no filetype", vim.log.levels.WARN)
        return
    end

    local compatible = lsp_manager.get_compatible_lsp_for_ft(ft)
    local server_names = {}
    for _, name in ipairs(compatible) do
        if
            not lsp_manager.is_server_disabled_globally(name)
            and not lsp_manager.is_server_disabled_for_buffer(name, current_bufnr)
        then
            table.insert(server_names, name)
        end
    end
    table.sort(server_names)

    if #server_names == 0 then
        notify("No servers available for filetype: " .. ft, vim.log.levels.INFO)
        return
    end

    -- checked = not yet attached (i.e. candidates for reattach)
    local attached = {}
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = current_bufnr })) do
        attached[client.name] = true
    end

    local initial_selected = {}
    for _, name in ipairs(server_names) do
        if not attached[name] then
            initial_selected[name] = true
        end
    end

    local menus_cfg = (lsp_state.config.menus or {}).reattach or {}
    lsp_ui.get().multiselect({
        title = menus_cfg.title,
        subtitle = ft,
        items = server_names,
        initial_selected = initial_selected,
        callback = function(confirmed, selected)
            if not confirmed then
                return
            end
            for _, name in ipairs(server_names) do
                if selected and selected[name] then
                    lsp_manager.ensure_lsp_for_buffer(name, current_bufnr)
                end
            end
        end,
    })
end

-- ── lsp_restart ───────────────────────────────────────────────────────────────

local function lsp_restart()
    local running_clients = vim.lsp.get_clients()
    if #running_clients == 0 then
        notify("No LSP servers are running.", vim.log.levels.INFO)
        return
    end

    local seen = {}
    local server_names = {}
    for _, client in ipairs(running_clients) do
        if not seen[client.name] then
            seen[client.name] = true
            table.insert(server_names, client.name)
        end
    end
    table.sort(server_names)

    local initial_selected = {}
    for _, name in ipairs(server_names) do
        initial_selected[name] = true
    end

    local function do_restart(selected)
        if not selected or vim.tbl_isempty(selected) then
            return
        end
        local count = 0
        for server_name in pairs(selected) do
            local attached_bufs = {}
            for _, client in ipairs(running_clients) do
                if client.name == server_name then
                    for bufnr in pairs(client.attached_buffers or {}) do
                        table.insert(attached_bufs, bufnr)
                    end
                    pcall(client.stop, client)
                end
            end
            vim.defer_fn(function()
                local ok, new_cid = pcall(lsp_manager.start_language_server, server_name, true)
                if ok and new_cid then
                    for _, bufnr in ipairs(attached_bufs) do
                        pcall(vim.lsp.buf_attach_client, bufnr, new_cid)
                    end
                end
            end, 500)
            count = count + 1
        end
        if count > 0 then
            notify("Restarting " .. count .. " LSP server(s)...", vim.log.levels.INFO)
        end
    end

    local menus_cfg = (lsp_state.config.menus or {}).restart or {}
    lsp_ui.get().multiselect({
        title = menus_cfg.title,
        subtitle = menus_cfg.subtitle,
        items = server_names,
        initial_selected = initial_selected,
        callback = function(confirmed, selected)
            if not confirmed then
                return
            end
            do_restart(selected)
        end,
    })
end

-- ── lsp_info ──────────────────────────────────────────────────────────────────
-- Delegates to lvim-lsp.ui.info — all rendering logic lives there.

local function lsp_info()
    return ui_info.show()
end

-- ── Registration ──────────────────────────────────────────────────────────────

local M = {}

--- Invisible border (padding without a visible frame).
local _border = {
    { " ", "FloatBorder" },
    { " ", "FloatBorder" },
    { " ", "FloatBorder" },
    { " ", "FloatBorder" },
    { " ", "FloatBorder" },
    { " ", "FloatBorder" },
    { " ", "FloatBorder" },
    { " ", "FloatBorder" },
}

--- Register all user commands.  Called once from bootstrap.
function M.setup()
    local diag_cfg = state.config.diagnostics

    -- ── helpers ───────────────────────────────────────────────────────────────

    local function require_method(method, fn)
        return function(opts)
            local clients = vim.lsp.get_clients({ bufnr = 0, method = method })
            if #clients == 0 then
                notify("No LSP client supporting " .. method .. " found", vim.log.levels.WARN)
                return
            end
            fn(opts)
        end
    end

    local function require_client(fn)
        return function(opts)
            if #vim.lsp.get_clients({ bufnr = 0 }) == 0 then
                notify("No active LSP client found", vim.log.levels.WARN)
                return
            end
            fn(opts)
        end
    end

    -- Route a "locations" command to its configured presentation: "native" runs the built-in handler,
    -- everything else opens the public lvim-utils PICKER in that layout — "area" (the cmdheight/msgarea
    -- zone, the default), "float" (a centred float), or "split"/"bottom" (a bottom dock). See config.peek.
    ---@param method string
    ---@param native_fn fun()
    local function present(method, native_fn)
        local mode = (lsp_state.config.peek or {})[method] or "area"
        if mode == "native" then
            native_fn()
        else
            local layout = (mode == "split" or mode == "bottom") and "bottom" or (mode == "float" and "float") or "area"
            require("lvim-lsp.ui.locations").open(method, layout)
        end
    end

    -- ── subcommand dispatch table ─────────────────────────────────────────────

    local subcommands = {
        hover = require_method("textDocument/hover", function()
            if (lsp_state.config.hover or {}).enabled then
                require("lvim-lsp.ui.hover").open()
            else
                vim.lsp.buf.hover({ border = _border })
            end
        end),
        rename = require_method("textDocument/rename", function()
            vim.lsp.buf.rename(nil, { border = _border })
        end),
        format = require_method("textDocument/formatting", function()
            vim.lsp.buf.format({ async = false })
        end),
        code_action = require_method("textDocument/codeAction", function()
            vim.lsp.buf.code_action({ border = _border })
        end),
        definition = require_method("textDocument/definition", function()
            present("definition", function()
                vim.lsp.buf.definition()
            end)
        end),
        type_definition = require_method("textDocument/typeDefinition", function()
            present("type_definition", function()
                vim.lsp.buf.type_definition()
            end)
        end),
        declaration = require_method("textDocument/declaration", function()
            present("declaration", function()
                vim.lsp.buf.declaration()
            end)
        end),
        references = require_method("textDocument/references", function()
            present("references", function()
                vim.lsp.buf.references(nil, { border = _border })
            end)
        end),
        implementation = require_method("textDocument/implementation", function()
            present("implementation", function()
                vim.lsp.buf.implementation()
            end)
        end),
        signature_help = require_method("textDocument/signatureHelp", function()
            vim.lsp.buf.signature_help({ border = _border })
        end),
        document_symbol = require_method("textDocument/documentSymbol", function()
            vim.lsp.buf.document_symbol()
        end),
        -- Document Symbols outline — a persistent side-split panel (neo-tree style).
        outline = function()
            require("lvim-lsp.ui.outline").toggle()
        end,
        outline_focus = function()
            require("lvim-lsp.ui.outline").focus()
        end,
        workspace_symbol = require_method("workspace/symbol", function()
            local mode = (lsp_state.config.peek or {}).workspace_symbol or "native"
            if mode == "split" or mode == "float" then
                require("lvim-lsp.ui.symbols").workspace(mode)
            else
                vim.lsp.buf.workspace_symbol()
            end
        end),
        document_highlight = require_method("textDocument/documentHighlight", function()
            vim.lsp.buf.document_highlight()
        end),
        clear_references = require_method("textDocument/documentHighlight", function()
            vim.lsp.buf.clear_references()
        end),
        incoming_calls = require_method("textDocument/prepareCallHierarchy", function()
            local mode = (lsp_state.config.peek or {}).calls or "native"
            if mode == "split" or mode == "float" then
                require("lvim-lsp.ui.calls").open("incoming", mode)
            else
                vim.lsp.buf.incoming_calls()
            end
        end),
        outgoing_calls = require_method("textDocument/prepareCallHierarchy", function()
            local mode = (lsp_state.config.peek or {}).calls or "native"
            if mode == "split" or mode == "float" then
                require("lvim-lsp.ui.calls").open("outgoing", mode)
            else
                vim.lsp.buf.outgoing_calls()
            end
        end),
        add_workspace_folder = require_method("workspace/didChangeWorkspaceFolders", function()
            vim.lsp.buf.add_workspace_folder()
        end),
        remove_workspace_folder = require_method("workspace/didChangeWorkspaceFolders", function()
            vim.lsp.buf.remove_workspace_folder()
        end),
        list_workspace_folders = require_client(function()
            local folders = vim.lsp.buf.list_workspace_folders() or {}
            if #folders == 0 then
                notify("No workspace folders.", vim.log.levels.INFO)
                return
            end
            notify("Workspace folders:\n" .. table.concat(folders, "\n"), vim.log.levels.INFO)
        end),
        range_format = require_method("textDocument/rangeFormatting", function(opts)
            vim.lsp.buf.format({
                range = { ["start"] = { opts.line1, 0 }, ["end"] = { opts.line2, 0 } },
                async = false,
            })
        end),
        diagnostic_current = require_client(function()
            if diag_cfg.show_line then
                diag_cfg.show_line()
            else
                require("lvim-lsp.ui.diagnostic").current()
            end
        end),
        diagnostic_next = require_client(function()
            if diag_cfg.goto_next then
                diag_cfg.goto_next()
            else
                require("lvim-lsp.ui.diagnostic").next()
            end
        end),
        diagnostic_prev = require_client(function()
            if diag_cfg.goto_prev then
                diag_cfg.goto_prev()
            else
                require("lvim-lsp.ui.diagnostic").prev()
            end
        end),
        -- Two-pane diagnostics navigator. "float"/"split" open the lvim-utils peek with a scope +
        -- severity filter bar; "native" (or any other value) falls back to the quickfix list.
        diagnostics = require_client(function()
            local mode = (lsp_state.config.peek or {}).diagnostics or "split"
            if mode == "split" or mode == "float" then
                require("lvim-lsp.ui.diagnostics_list").open(mode)
            else
                vim.diagnostic.setqflist()
            end
        end),
        -- Toggle inlay hints for the current buffer (Neovim 0.10+).
        toggle_inlay_hints = require_client(function()
            local ih = vim.lsp.inlay_hint
            if not (ih and ih.enable) then
                notify("Inlay hints require Neovim 0.10+.", vim.log.levels.WARN)
                return
            end
            local on = ih.is_enabled({ bufnr = 0 })
            ih.enable(not on, { bufnr = 0 })
            notify("Inlay hints " .. (on and "disabled" or "enabled") .. ".", vim.log.levels.INFO)
        end),
        -- Toggle CodeLens for the current buffer (clears / refreshes lenses).
        toggle_codelens = require_method("textDocument/codeLens", function()
            local b = vim.api.nvim_get_current_buf()
            if vim.b[b].lvim_lsp_codelens_off then
                vim.b[b].lvim_lsp_codelens_off = nil
                vim.lsp.codelens.refresh({ bufnr = b })
                notify("CodeLens enabled.", vim.log.levels.INFO)
            else
                vim.b[b].lvim_lsp_codelens_off = true
                vim.lsp.codelens.clear(nil, b)
                notify("CodeLens disabled.", vim.log.levels.INFO)
            end
        end),
        toggle_servers = toggle_servers_globally,
        toggle_servers_buffer = function(opts)
            toggle_servers_for_buffer(tonumber(opts.args))
        end,
        restart = lsp_restart,
        info = lsp_info,
        log = function()
            -- Open the engine's debug log (the logger lives in lvim-ls; path mirrors
            -- lvim-ls/utils/debug.lua) in a read-only split.
            local path = vim.fn.stdpath("state") .. "/lvim-ls/debug.log"
            if vim.fn.filereadable(path) == 0 then
                local enabled = (state.config.debug or {}).enabled
                notify(
                    "No debug log yet" .. (enabled and "." or " — set debug.enabled = true in setup() first."),
                    vim.log.levels.WARN
                )
                return
            end
            vim.cmd("botright split " .. vim.fn.fnameescape(path))
            vim.bo.modifiable = false
        end,
        reattach = lsp_reattach,
        project = function()
            ui_project.open(vim.api.nvim_get_current_buf())
        end,
        declined = function()
            local ok, pkg = pcall(require, "lvim-pkg")
            if not ok then
                notify("lvim-pkg is unavailable.", vim.log.levels.WARN)
                return
            end
            local declines = pkg.declined()
            if #declines == 0 then
                notify("No declined packages.", vim.log.levels.INFO)
                return
            end
            -- "<ft>: <name>" labels, mapped back to their { ft, name } record.
            local items, by_label = {}, {}
            for _, d in ipairs(declines) do
                local label = d.ft .. ": " .. d.name
                items[#items + 1] = label
                by_label[label] = d
            end
            table.sort(items)
            -- All items initially checked (= currently declined).
            -- Unchecking re-enables that package for its filetype.
            local initial = {}
            for _, label in ipairs(items) do
                initial[label] = true
            end
            local menus_cfg = (lsp_state.config.menus or {}).declined or {}
            lsp_ui.get().multiselect({
                title = menus_cfg.title,
                subtitle = menus_cfg.subtitle,
                items = items,
                initial_selected = initial,
                callback = function(confirmed, selected)
                    if not confirmed then
                        return
                    end
                    local count = 0
                    for _, label in ipairs(items) do
                        if not selected or not selected[label] then
                            local d = by_label[label]
                            pkg.undecline(d.ft, d.name)
                            count = count + 1
                        end
                    end
                    if count > 0 then
                        notify(
                            string.format("Re-enabled %d package(s). Open a file to be offered them again.", count),
                            vim.log.levels.INFO
                        )
                    end
                end,
            })
        end,
    }

    if state.config.dap_local_fn then
        subcommands.dap = function()
            state.config.dap_local_fn()
        end
    end

    local subcommand_names = vim.tbl_keys(subcommands)
    table.sort(subcommand_names)

    -- ── single entry-point command ────────────────────────────────────────────

    vim.api.nvim_create_user_command("LvimLsp", function(opts)
        local sub = opts.fargs[1]
        local fn = subcommands[sub]
        if not fn then
            notify("LvimLsp: unknown subcommand '" .. tostring(sub) .. "'", vim.log.levels.ERROR)
            return
        end
        fn(opts)
    end, {
        nargs = "+",
        range = true,
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
