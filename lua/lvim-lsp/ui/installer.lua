-- lvim-lsp: custom Mason-backed installer UI.
-- Provides a floating progress popup that tracks one or more Mason package
-- installations in parallel, showing a braille spinner, per-tool status
-- (pending / ok / fail), and the latest stdout/stderr action line.
-- Exposes M.ensure_mason_tools(tools, cb) and M.status() debug helper.
--
---@module "lvim-lsp.installer"
---@diagnostic disable: undefined-doc-name, undefined-field

local api   = vim.api
local state = require("lvim-lsp.state")

-- ── Constants (resolved lazily from state.config at call-time) ────────────────

local HL_TITLE          = "MasonTitle"
local HL_POPUP_BG       = "MasonPopupBG"
local HL_PKG_NAME       = "MasonPkgName"
local HL_ICON_PROGRESS  = "MasonIconProgress"
local HL_ICON_OK        = "MasonIconOk"
local HL_ICON_ERROR     = "MasonIconError"
local HL_CURRENT_ACTION = "MasonCurrentAction"

---@type string[]
local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local ICON_OK    = ""
local ICON_ERROR = ""

---@type { PENDING: string, OK: string, FAIL: string }
local STATUS = { PENDING = "pending", OK = "ok", FAIL = "fail" }

---@type table<string, string>
local STATUS_TEXT = {
    [STATUS.PENDING] = "Installing",
    [STATUS.OK]      = "Installed",
    [STATUS.FAIL]    = "Error",
}

---@type uv_timer_t|nil
local refresh_timer = nil
---@type uv_timer_t|nil
local keep_alive_timer = nil

---@class AllinOne
---@field tools               string[]
---@field win                 integer|nil
---@field bufnr               integer|nil
---@field states              table<string, table>
---@field ns                  integer
---@field callbacks           { tools: string[], callback: function }[]
---@field closed              boolean
---@field start_time          integer|nil
---@field active_installations integer
---@field is_installing       boolean
local allin1 = {
    tools               = {},
    win                 = nil,
    bufnr               = nil,
    states              = {},
    ns                  = api.nvim_create_namespace("lvim_lsp_installer_progress"),
    callbacks           = {},
    closed              = false,
    start_time          = nil,
    active_installations = 0,
    is_installing       = false,
}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function center_text(text, width)
    local pad = math.max(0, math.floor((width - #text) / 2))
    return string.rep(" ", pad) .. text
end

local function build_lines(tools, states)
    local popup_width = state.config.installer.popup_width
    local lines       = {}
    local line_meta   = {}

    local title = center_text(state.config.installer.popup_title, popup_width)
    table.insert(lines, title)
    table.insert(line_meta, {})

    for _, tool in ipairs(tools) do
        local s = states[tool]
        if not s then
            goto continue
        end

        table.insert(lines, tool)
        table.insert(line_meta, { pkg_name = true })

        local icon_str, icon_hl
        local spinner_frame = (s.spinner_frame or 1) % #SPINNER_FRAMES
        if s.status == STATUS.PENDING then
            icon_str = SPINNER_FRAMES[spinner_frame + 1]
            icon_hl  = HL_ICON_PROGRESS
        elseif s.status == STATUS.OK then
            icon_str = ICON_OK
            icon_hl  = HL_ICON_OK
        elseif s.status == STATUS.FAIL then
            icon_str = ICON_ERROR
            icon_hl  = HL_ICON_ERROR
        else
            icon_str = " "
            icon_hl  = nil
        end

        local status_text = STATUS_TEXT[s.status] or ""
        table.insert(lines, "    " .. icon_str .. " " .. status_text)
        table.insert(line_meta, {
            status   = true,
            icon_hl  = icon_hl,
            icon_len = vim.fn.strdisplaywidth(icon_str) + 1,
        })

        local current_action = s.current_action or ""
        table.insert(lines, "    " .. current_action)
        table.insert(line_meta, { current_action = true })

        table.insert(lines, "")
        table.insert(line_meta, {})

        ::continue::
    end

    return lines, line_meta
end

local function update_popup()
    if allin1.closed then
        return
    end
    if not allin1.tools or #allin1.tools == 0 then
        if allin1.win and api.nvim_win_is_valid(allin1.win) then
            api.nvim_win_close(allin1.win, true)
        end
        allin1.win   = nil
        allin1.bufnr = nil
        return
    end

    local popup_width              = state.config.installer.popup_width
    local lines, line_meta = build_lines(allin1.tools, allin1.states)
    local height           = #lines
    local col              = vim.o.columns - popup_width
    local row              = 1

    if allin1.win and api.nvim_win_is_valid(allin1.win) then
        pcall(api.nvim_win_set_config, allin1.win, {
            relative = "editor",
            width    = popup_width,
            height   = height,
            row      = row,
            col      = col,
        })
        pcall(api.nvim_buf_set_lines, allin1.bufnr, 0, -1, false, lines)
    else
        local bufnr = api.nvim_create_buf(false, true)
        vim.bo[bufnr].bufhidden  = "wipe"
        vim.bo[bufnr].modifiable = true
        api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        allin1.win = api.nvim_open_win(bufnr, false, {
            style     = "minimal",
            relative  = "editor",
            width     = popup_width,
            height    = height,
            row       = row,
            col       = col,
            border    = "rounded",
            focusable = false,
            zindex    = 250,
            noautocmd = true,
        })
        allin1.bufnr = bufnr
        api.nvim_set_option_value(
            "winhighlight",
            "Normal:" .. HL_POPUP_BG .. ",NormalNC:" .. HL_POPUP_BG,
            { win = allin1.win }
        )
    end

    if allin1.bufnr then
        pcall(api.nvim_buf_clear_namespace, allin1.bufnr, allin1.ns, 0, -1)
        pcall(vim.highlight.range, allin1.bufnr, allin1.ns, HL_TITLE, { 0, 0 }, { 0, -1 })
        for i, meta in ipairs(line_meta) do
            local line_idx = i - 1
            if meta.pkg_name then
                pcall(vim.highlight.range, allin1.bufnr, allin1.ns, HL_PKG_NAME, { line_idx, 0 }, { line_idx, -1 })
            elseif meta.current_action then
                pcall(vim.highlight.range, allin1.bufnr, allin1.ns, HL_CURRENT_ACTION, { line_idx, 0 }, { line_idx, -1 })
            elseif meta.status and meta.icon_hl and meta.icon_len > 0 then
                pcall(vim.highlight.range, allin1.bufnr, allin1.ns, meta.icon_hl,
                    { line_idx, 4 }, { line_idx, 4 + meta.icon_len })
            end
        end
    end
end

local function close_popup(force)
    if not force and allin1.is_installing then
        return
    end
    if refresh_timer and not refresh_timer:is_closing() then
        refresh_timer:stop()
        refresh_timer:close()
        refresh_timer = nil
    end
    if keep_alive_timer and not keep_alive_timer:is_closing() then
        keep_alive_timer:stop()
        keep_alive_timer:close()
        keep_alive_timer = nil
    end
    allin1.closed = true
    if allin1.win and api.nvim_win_is_valid(allin1.win) then
        api.nvim_win_close(allin1.win, true)
    end
    allin1.win   = nil
    allin1.bufnr = nil
    vim.defer_fn(function()
        allin1.tools                = {}
        allin1.states               = {}
        allin1.callbacks            = {}
        allin1.closed               = false
        allin1.active_installations = 0
        allin1.is_installing        = false
    end, 200)
end

local function update_current_action(tool, line)
    if not allin1.states[tool] then
        return
    end
    line = vim.trim(line)
    if line == "" then
        return
    end
    if line:match("^ERROR: ") then
        line = line:gsub("^ERROR: ", "")
    end
    allin1.states[tool].current_action = line
    if #line < 30 then
        allin1.states[tool].message = line
    end
    update_popup()
end

local function start_keep_alive_timer()
    if keep_alive_timer and not keep_alive_timer:is_closing() then
        keep_alive_timer:stop()
        keep_alive_timer:close()
    end
    keep_alive_timer = vim.loop.new_timer()
    keep_alive_timer:start(1000, 1000, vim.schedule_wrap(function()
        if allin1.is_installing then
            if not allin1.win or not api.nvim_win_is_valid(allin1.win) then
                allin1.closed = false
                update_popup()
            end
        end
    end))
end

local function add_tools(new_tools)
    local mason_registry_ok, mason_registry = pcall(require, "mason-registry")
    if not mason_registry_ok then
        vim.notify("Error loading mason-registry", vim.log.levels.ERROR)
        return {}
    end
    local actually_added = {}
    for _, name in ipairs(new_tools) do
        local already = false
        for _, t in ipairs(allin1.tools) do
            if t == name then
                already = true
                break
            end
        end
        if not already then
            local ok, pkg = pcall(mason_registry.get_package, name)
            if ok and pkg then
                local mason_bin     = vim.fn.stdpath("data") .. "/mason/bin/" .. name
                local binary_ok     = vim.fn.executable(name) == 1
                    or vim.fn.executable(mason_bin) == 1
                local needs_install = not pkg:is_installed() or not binary_ok
                -- Track whether we need force-reinstall (metadata says installed but binary gone)
                local force_reinstall = pkg:is_installed() and not binary_ok
                if needs_install then
                    table.insert(allin1.tools, name)
                    allin1.states[name] = {
                        status         = STATUS.PENDING,
                        current_action = "Preparing installation...",
                        spinner_frame  = 0,
                        message        = "Preparing...",
                        start_time     = os.time(),
                        force_reinstall = force_reinstall,
                    }
                    allin1.active_installations = allin1.active_installations + 1
                    allin1.is_installing        = true
                    table.insert(actually_added, name)
                end
            end
        end
    end
    return actually_added
end

local function are_tools_completed(tools)
    for _, tool in ipairs(tools) do
        if allin1.states[tool] and allin1.states[tool].status == STATUS.PENDING then
            return false
        end
    end
    return true
end

local function check_callbacks()
    local to_remove = {}
    for i, cb_data in ipairs(allin1.callbacks) do
        if are_tools_completed(cb_data.tools) then
            if cb_data.callback then
                cb_data.callback()
            end
            table.insert(to_remove, i)
        end
    end
    for i = #to_remove, 1, -1 do
        table.remove(allin1.callbacks, to_remove[i])
    end

    if are_tools_completed(allin1.tools) and allin1.active_installations == 0 then
        local manager = require("lvim-lsp.core.manager")
        pcall(manager.set_installation_status, false)
        allin1.is_installing = false
        vim.defer_fn(function()
            close_popup(false)
        end, 10000)
    end
end

local function start_ui_refresh_timer()
    if refresh_timer and not refresh_timer:is_closing() then
        refresh_timer:stop()
        refresh_timer:close()
    end
    local hide_delay = state.config.installer.hide_installed_delay
    refresh_timer = vim.loop.new_timer()
    refresh_timer:start(0, 50, vim.schedule_wrap(function()
        if allin1.closed then
            if refresh_timer and not refresh_timer:is_closing() then
                refresh_timer:stop()
                refresh_timer:close()
                refresh_timer = nil
            end
            return
        end

        for _, tool in ipairs(allin1.tools) do
            local s = allin1.states[tool]
            if s and s.status == STATUS.PENDING then
                s.spinner_frame = (s.spinner_frame or 0) + 1
            end
        end

        local changed  = false
        local to_remove = {}
        for _, tool in ipairs(allin1.tools) do
            local s = allin1.states[tool]
            if s and s.status == STATUS.OK and not s.hide_timer_started then
                s.hide_timer_started = true
                s.hide_time = os.time() + hide_delay
            end
            if s and s.status == STATUS.OK and s.hide_time and os.time() >= s.hide_time then
                table.insert(to_remove, tool)
            end
        end

        if #to_remove > 0 then
            for _, tool in ipairs(to_remove) do
                for i, t in ipairs(allin1.tools) do
                    if t == tool then
                        table.remove(allin1.tools, i)
                        break
                    end
                end
                allin1.states[tool] = nil
            end
            changed = true
        end

        if changed and #allin1.tools == 0 and not allin1.is_installing then
            if allin1.win and api.nvim_win_is_valid(allin1.win) then
                api.nvim_win_close(allin1.win, true)
            end
            allin1.win   = nil
            allin1.bufnr = nil
        end

        pcall(update_popup)
    end))
end

-- ── Public API ────────────────────────────────────────────────────────────────

local M = {}

--- Ensures that all `tools` are installed via Mason.
--- Already-installed tools are skipped.  When all finish (or were already
--- present) `cb` is invoked once.  Diagnostics are reset on all loaded
--- buffers before `cb` runs.
---@param tools string[]
---@param cb    function|nil
M.ensure_mason_tools = function(tools, cb)
    local mason_registry_ok, mason_registry = pcall(require, "mason-registry")
    if not mason_registry_ok then
        vim.notify("Error loading mason-registry", vim.log.levels.ERROR)
        if cb then cb() end
        return
    end

    local manager = require("lvim-lsp.core.manager")

    tools = tools or {}
    if #tools == 0 then
        if cb then cb() end
        return
    end

    if cb then
        local original_callback = cb
        local wrapped_callback  = function()
            for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
                    vim.diagnostic.reset(nil, bufnr)
                end
            end
            original_callback()
        end
        table.insert(allin1.callbacks, {
            tools    = vim.deepcopy(tools),
            callback = wrapped_callback,
        })
    end

    allin1.start_time = os.time()

    local new_tools = add_tools(tools)
    if #new_tools == 0 then
        -- All tools already installed — fire callback immediately without calling
        -- set_installation_status, which would schedule a server restart and
        -- cause an infinite loop (restart → ensure_lsp_for_buffer → here again).
        allin1.is_installing = false
        check_callbacks()
        return
    end

    manager.set_installation_status(true)
    allin1.is_installing = true

    allin1.closed = false
    start_ui_refresh_timer()
    start_keep_alive_timer()
    update_popup()

    -- Install tools one at a time — Mason does not handle concurrent pkg:install()
    -- calls reliably; the second package often fails when both run in parallel.
    local function install_one(idx)
        if idx > #new_tools then
            return
        end
        local tool = new_tools[idx]
        if not (allin1.states[tool] and allin1.states[tool].status == STATUS.PENDING) then
            install_one(idx + 1)
            return
        end

        local pkg = mason_registry.get_package(tool)
        if not pkg then
            allin1.states[tool].status         = STATUS.FAIL
            allin1.states[tool].current_action = "Package not found"
            allin1.active_installations        = math.max(0, allin1.active_installations - 1)
            update_popup()
            install_one(idx + 1)
            return
        end

        update_current_action(tool, "Starting installation...")

        local install_ok, install_result = pcall(function()
            local opts = (allin1.states[tool].force_reinstall) and { force = true } or {}
            return pkg:install(opts)
        end)
        if not install_ok then
            allin1.states[tool].status         = STATUS.FAIL
            allin1.states[tool].current_action = "Failed to start: " .. tostring(install_result)
            allin1.active_installations        = math.max(0, allin1.active_installations - 1)
            update_popup()
            install_one(idx + 1)
            return
        end

        local handle = install_result
        if not handle then
            allin1.states[tool].status         = STATUS.FAIL
            allin1.states[tool].current_action = "No installation handle returned"
            allin1.active_installations        = math.max(0, allin1.active_installations - 1)
            update_popup()
            install_one(idx + 1)
            return
        end

        handle:on("stdout", vim.schedule_wrap(function(chunk)
            if allin1.closed or not allin1.states or not allin1.states[tool] then return end
            if chunk and #chunk > 0 then
                local best_line = ""
                for line in chunk:gmatch("[^\r\n]+") do
                    if line and #line > 0 and not line:match("^%s*%*+%s*$") then
                        best_line = line
                    end
                end
                if best_line ~= "" then
                    update_current_action(tool, best_line)
                end
            end
        end))

        handle:on("stderr", vim.schedule_wrap(function(chunk)
            if allin1.closed or not allin1.states or not allin1.states[tool] then return end
            if chunk and #chunk > 0 then
                for line in chunk:gmatch("[^\r\n]+") do
                    if line and #line > 0 then
                        update_current_action(tool, line)
                    end
                end
            end
        end))

        handle:on("progress", vim.schedule_wrap(function(progress)
            if allin1.closed or not allin1.states or not allin1.states[tool] then return end
            if progress.message then
                update_current_action(tool, progress.message)
                allin1.states[tool].message = progress.message
            end
            update_popup()
        end))

        handle:once("closed", vim.schedule_wrap(function()
            vim.defer_fn(function()
                if not allin1 or not allin1.states or not allin1.states[tool] then
                    install_one(idx + 1)
                    return
                end

                -- Primary check: binary existence in PATH or Mason bin dir.
                -- pkg:is_installed() can return stale/false results right after
                -- install because Mason caches package state internally.
                local bin_path = vim.fn.stdpath("data") .. "/mason/bin/" .. tool
                local installed = vim.fn.executable(tool) == 1
                    or vim.fn.executable(bin_path) == 1
                -- Fallback to Mason metadata in case binary name differs from package name.
                if not installed then
                    pcall(function()
                        local fresh_pkg = require("mason-registry").get_package(tool)
                        if fresh_pkg then installed = fresh_pkg:is_installed() end
                    end)
                end

                if allin1.states and allin1.states[tool] then
                    if installed then
                        update_current_action(tool, "Installation completed successfully")
                        allin1.states[tool].status             = STATUS.OK
                        allin1.states[tool].message            = "Installation complete"
                        allin1.states[tool].hide_timer_started = false
                        allin1.states[tool].hide_time          = nil
                    else
                        update_current_action(tool, "Installation failed")
                        allin1.states[tool].status  = STATUS.FAIL
                        allin1.states[tool].message = "Installation failed"
                    end
                    allin1.active_installations = math.max(0, allin1.active_installations - 1)
                    if allin1.active_installations == 0 then
                        vim.defer_fn(function()
                            if allin1.active_installations == 0 then
                                allin1.is_installing = false
                            end
                        end, 1000)
                    end
                end
                update_popup()
                pcall(check_callbacks)
                -- Start the next tool only after this one has finished.
                install_one(idx + 1)
            end, 500)
        end))
    end

    install_one(1)
end

--- Prints a debug summary of the current installer state.
M.status = function()
    local tools_list = table.concat(allin1.tools, ", ")
    vim.notify(string.format(
        "Active = %d, Installing = %s, Tools: %s",
        allin1.active_installations,
        allin1.is_installing and "YES" or "NO",
        #allin1.tools > 0 and tools_list or "none"
    ), vim.log.levels.INFO)
    for tool, s in pairs(allin1.states) do
        vim.notify(
            string.format("%s: %s, Action: %s", tool, s.status or "unknown", s.current_action or ""),
            vim.log.levels.INFO
        )
    end
end

return M
