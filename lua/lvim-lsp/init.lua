-- lvim-lsp: public API entry point.
-- Call require("lvim-lsp").setup(opts) once in your config.
-- All other public functions are re-exported here so callers never need to
-- reach into sub-modules directly.
--
---@module "lvim-lsp"

local lsp_state = require("lvim-lsp.state")
local ui_info = require("lvim-lsp.ui.info")
local ui_progress = require("lvim-lsp.ui.progress")
local lsp_ui = require("lvim-lsp.ui")
local lsp_commands = require("lvim-lsp.core.commands")
local ls_state = require("lvim-ls.state")
local ls_manager = require("lvim-ls.core.manager")
local ls_features = require("lvim-ls.core.features")
local ls_progress = require("lvim-ls.core.progress")
local ls_globals = require("lvim-ls.core.globals")
local ls_bootstrap = require("lvim-ls.core.bootstrap")
local ls_data = require("lvim-ls.data")

local M = {}

--- Configure and activate the LSP manager.
--- Must be called before any other function in this module.
---@param opts LvimLspConfig
function M.setup(opts)
    local state = ls_state
    local commands = lsp_commands
    local bootstrap = ls_bootstrap

    local features = ls_features

    -- Split opts: UI keys go to lvim-lsp's own UI state; the rest to the engine. This
    -- keeps lvim-ls.state.config pure data (no UI), like lvim-pkg vs lvim-installer.
    local UI_KEYS = {
        popup_global = true,
        form = true,
        menus = true,
        project = true,
        info = true,
        build = true,
        force = true,
        highlights = true,
        peek = true,
        hover = true,
    }
    local data_opts, ui_opts = {}, {}
    for k, v in pairs(opts or {}) do
        if UI_KEYS[k] then
            ui_opts[k] = v
        else
            data_opts[k] = v
        end
    end
    -- progress config is split: behaviour → engine, appearance → UI.
    if opts and opts.progress then
        local P_UI = { spinner = true, done_icon = true, render_limit = true, panel = true, highlights = true }
        local p_data, p_ui = {}, {}
        for k, v in pairs(opts.progress) do
            if P_UI[k] then
                p_ui[k] = v
            else
                p_data[k] = v
            end
        end
        data_opts.progress = p_data
        ui_opts.progress = p_ui
    end
    local ui_state = lsp_state
    ui_state.configure(ui_opts)
    local ui_cfg = ui_state.config
    state.configure(data_opts)
    -- Reset the UI's cached config (lives here now — the engine stays UI-agnostic).
    lsp_ui.reset()
    ls_globals.load()

    local ok, hl = pcall(require, "lvim-utils.highlight")
    if ok then
        -- Ensure lvim-utils UI groups are registered so popups are colored even
        -- when require("lvim-utils").setup() has not been called directly.
        local utils_ok, utils_cfg = pcall(require, "lvim-utils.config")
        if utils_ok then
            hl.register(utils_cfg.colors)
        end

        -- Use build_highlights() instead of a pre-computed snapshot so we always
        -- read the current palette (snapshot may contain nil colors at load time).
        local build_hl = ui_cfg.build
        local force = ui_cfg.force or false
        hl.register(build_hl(), force)
        -- User-provided overrides from setup({ highlights = { ... } }) always win.
        if ui_cfg.highlights and not vim.tbl_isempty(ui_cfg.highlights) then
            hl.register(ui_cfg.highlights, true)
        end

        -- Install the ColorScheme autocmd so all registered groups survive a
        -- generic colorscheme change (e.g. :colorscheme foo).
        hl.setup()

        -- Re-register LvimLsp* groups whenever the palette changes (e.g. after
        -- lvim-colorscheme syncs).  build_highlights() re-reads c.* so new colors land.
        local colors_ok, colors = pcall(require, "lvim-utils.colors")
        if colors_ok then
            colors.on_change(function()
                hl.register(ui_cfg.build(), ui_cfg.force or false)
                if ui_cfg.highlights and not vim.tbl_isempty(ui_cfg.highlights) then
                    hl.register(ui_cfg.highlights, true)
                end
            end)
        end
    end

    features.setup_diagnostics()
    features.setup_code_lens()
    ls_progress.setup()
    ui_progress.setup()
    commands.setup()

    bootstrap.init()
end

-- ── Re-exports (data) ─────────────────────────────────────────────────────────

--- Missing tools for filetype `ft`, grouped by the server that requires them.
--- Pure data for the unified installer prompt; performs no installation.
---@param ft string
---@return table<string, string[]>
function M.missing_for_ft(ft)
    return ls_data.missing_for_ft(ft)
end

-- ── Re-exports (manager) ──────────────────────────────────────────────────────

--- Start or attach an LSP server to a buffer.
---@param server_name string
---@param bufnr       integer
---@return integer|nil
function M.ensure_lsp_for_buffer(server_name, bufnr)
    return ls_manager.ensure_lsp_for_buffer(server_name, bufnr)
end

--- Register EFM tool configs and restart EFM.
---@param filetypes    string[]
---@param tools_config table[]
function M.setup_efm(filetypes, tools_config)
    ls_manager.setup_efm(filetypes, tools_config)
end

--- Start an LSP server (optionally force-attach to all compatible buffers).
---@param server_name string
---@param force       boolean
---@return integer|nil
function M.start_language_server(server_name, force)
    return ls_manager.start_language_server(server_name, force)
end

--- Disable a server globally (stops all running instances).
---@param server_name string
function M.disable_lsp_server_globally(server_name)
    ls_manager.disable_lsp_server_globally(server_name)
end

--- Re-enable a previously disabled server globally.
---@param server_name string
function M.enable_lsp_server_globally(server_name)
    ls_manager.enable_lsp_server_globally(server_name)
end

--- Disable a server for a single buffer.
---@param server_name string
---@param bufnr       integer
function M.disable_lsp_server_for_buffer(server_name, bufnr)
    ls_manager.disable_lsp_server_for_buffer(server_name, bufnr)
end

--- Re-enable a server for a single buffer and immediately re-attach.
---@param server_name string
---@param bufnr       integer
function M.enable_lsp_server_for_buffer(server_name, bufnr)
    ls_manager.enable_lsp_server_for_buffer(server_name, bufnr)
end

--- Returns all server names compatible with filetype `ft`.
---@param ft string
---@return string[]
function M.get_compatible_lsp_for_ft(ft)
    return ls_manager.get_compatible_lsp_for_ft(ft)
end

--- Returns a read-only snapshot of module state (useful for debugging).
---@return table
function M.get_state()
    local state = ls_state
    return vim.deepcopy({
        clients_by_root = state.clients_by_root,
        disabled_servers = state.disabled_servers,
        disabled_for_buffer = state.disabled_for_buffer,
        efm_configs = state.efm_configs,
        installation_in_progress = state.installation_in_progress,
        config = state.config,
    })
end

-- ── Progress ──────────────────────────────────────────────────────────────────

--- Toggle suppression of LSP progress tracking.
---@param bool boolean
function M.suppress_progress(bool)
    ls_progress.suppress(bool)
end

--- Clear all active progress entries and close the progress panel immediately.
---@return nil
function M.clear_progress()
    ls_progress.clear()
end

--- Returns a compact progress string suitable for statusline use.
--- Empty string when no progress is active.
---@return string
function M.get_progress_status()
    return ui_progress.get_status()
end

--- Compact statusline string of the LSP servers attached to `bufnr`, plus error/warning
--- diagnostic counts. Empty string when no client is attached. Example: "lua_ls, efm  E1 W2".
---@param bufnr? integer  defaults to the current buffer
---@return string
function M.get_attached_status(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local names = {}
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
        names[#names + 1] = client.name
    end
    if #names == 0 then
        return ""
    end
    table.sort(names)
    local out = table.concat(names, ", ")
    local counts = vim.diagnostic.count(bufnr)
    local parts = {}
    local e = counts[vim.diagnostic.severity.ERROR]
    local w = counts[vim.diagnostic.severity.WARN]
    if e and e > 0 then
        parts[#parts + 1] = "E" .. e
    end
    if w and w > 0 then
        parts[#parts + 1] = "W" .. w
    end
    if #parts > 0 then
        out = out .. "  " .. table.concat(parts, " ")
    end
    return out
end

-- ── Info window ───────────────────────────────────────────────────────────────

--- Open the rich LSP information floating window.
---@return { bufnr: integer, win: integer, close: fun() }|nil
function M.show_info()
    return ui_info.show()
end

return M
