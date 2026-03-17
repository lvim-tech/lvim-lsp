-- lvim-lsp: bootstrap — registers autocommands and the reattach command.
-- Scans the filetype of every newly-opened buffer and calls
-- manager.ensure_lsp_for_buffer() for each compatible, non-disabled server.
-- Also wires the DirChanged cleanup and an initial sweep of already-open buffers.
--
---@module "lvim-lsp.core.bootstrap"

local state       = require("lvim-lsp.state")
local lsp_manager = require("lvim-lsp.core.manager")

local M = {}

--- Inspects the filetype of `bufnr`, finds every server that supports it, and
--- attaches non-disabled servers.  EFM is attached when the filetype has a
--- registered tool config or is listed in state.efm_filetypes.
---@param bufnr integer
function M.attach_lsp_to_buffer(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    local ft = vim.bo[bufnr].filetype
    if not ft or ft == "" then
        return
    end

    local matches = {}
    for key, entry in pairs(state.file_types) do
        if vim.tbl_contains(entry.filetypes or {}, ft) then
            table.insert(matches, key)
        end
    end

    for _, match in ipairs(matches) do
        if
            not lsp_manager.is_server_disabled_globally(match)
            and not lsp_manager.is_server_disabled_for_buffer(match, bufnr)
        then
            lsp_manager.ensure_lsp_for_buffer(match, bufnr)
        end
    end

    -- Attach EFM when the filetype has a registered tool config or is in efm_filetypes
    if state.efm_configs[ft] or vim.tbl_contains(state.efm_filetypes, ft) then
        if
            not lsp_manager.is_server_disabled_globally("efm")
            and not lsp_manager.is_server_disabled_for_buffer("efm", bufnr)
        then
            lsp_manager.ensure_lsp_for_buffer("efm", bufnr)
        end
    end
end

--- Apply saved per-filetype editor options (.lvim-lsp/filetypes/<ft>.lua) to `bufnr`.
---@param bufnr integer
local function apply_ft_settings(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    local ft = vim.bo[bufnr].filetype
    if not ft or ft == "" then return end

    local root = vim.loop.cwd()
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
        if client.config and client.config.root_dir then
            root = client.config.root_dir
            break
        end
    end

    local settings = require("lvim-lsp.core.project").load_ft(root, ft)
    if vim.tbl_isempty(settings) then return end
    for k, v in pairs(settings) do
        pcall(function() vim.bo[bufnr][k] = v end)
    end
end

--- Detach and stop all LSP clients whose binary lives in `pkg`'s Mason directory.
--- Called on both uninstall:start (stop before files vanish) and uninstall:success
--- (cleanup any stragglers).  Detaching from buffers first prevents in-flight
--- LSP responses from trying to apply edits to non-modifiable buffers (E21).
---@param pkg table  Mason package object (pkg.name = Mason package name)
local function on_mason_uninstall(pkg)
    local pkg_name = pkg and pkg.name
    if not pkg_name then return end

    local pkg_dir = vim.fn.stdpath("data") .. "/mason/packages/" .. pkg_name
    for _, client in ipairs(vim.lsp.get_clients()) do
        local cmd = client.config and client.config.cmd
        local exe = type(cmd) == "table" and cmd[1] or ""
        if vim.startswith(exe, pkg_dir) or client.name == pkg_name then
            -- Detach from every buffer first so no in-flight response can write to them.
            for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_valid(bufnr) then
                    pcall(vim.lsp.buf_detach_client, bufnr, client.id)
                end
            end
            pcall(function()
                if type(client.stop) == "function" then
                    client:stop()
                end
            end)
        end
    end
end

--- Registers autocommands and performs an initial sweep of already-loaded
--- buffers so LSP servers attach immediately on startup.
function M.init()
    local group   = vim.api.nvim_create_augroup("LvimLspEnable", { clear = true })
    local startup = state.config.startup_delay_ms
    local dir_ms  = state.config.dir_change_delay_ms

    -- Stop LSP clients when Mason uninstalls their package.
    -- Listen on :start so the client stops before Mason deletes the binary files,
    -- preventing server crashes (missing modules) and stale in-flight LSP responses.
    local ok, mason_registry = pcall(require, "mason-registry")
    if ok and mason_registry then
        mason_registry:on("package:uninstall:start",   vim.schedule_wrap(on_mason_uninstall))
        mason_registry:on("package:uninstall:success", vim.schedule_wrap(on_mason_uninstall))
    end

    vim.defer_fn(function()
        -- Attach when Neovim sets the filetype on a buffer
        vim.api.nvim_create_autocmd("FileType", {
            group    = group,
            callback = function(args)
                M.attach_lsp_to_buffer(args.buf)
                apply_ft_settings(args.buf)
            end,
        })

        -- Re-check on BufEnter / BufReadPost with a short delay so the filetype
        -- option is guaranteed to be set before we inspect it
        vim.api.nvim_create_autocmd({ "BufEnter", "BufReadPost" }, {
            group    = group,
            callback = function(args)
                local bufnr = args.buf
                vim.defer_fn(function()
                    if vim.api.nvim_buf_is_valid(bufnr) then
                        M.attach_lsp_to_buffer(bufnr)
                        apply_ft_settings(bufnr)
                    end
                end, 100)
            end,
        })

        -- Stop servers from other projects after a directory change
        vim.api.nvim_create_autocmd("DirChanged", {
            pattern  = "*",
            group    = group,
            callback = function()
                vim.defer_fn(function()
                    lsp_manager.stop_servers_for_old_project()
                    if state.config.on_dir_change then
                        pcall(state.config.on_dir_change)
                    end
                end, dir_ms)
            end,
            desc = "Stop LSP servers from other projects on directory change",
        })

        -- Attach to any buffers that were already open before init() ran
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype ~= "" then
                M.attach_lsp_to_buffer(bufnr)
            end
        end
    end, startup)
end

return M
