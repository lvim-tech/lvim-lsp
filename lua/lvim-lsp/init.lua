-- lvim-lsp: public API entry point.
-- Call require("lvim-lsp").setup(opts) once in your config.
-- All other public functions are re-exported here so callers never need to
-- reach into sub-modules directly.
--
---@module "lvim-lsp"

local lsp_state = require("lvim-lsp.state")
local ui_info = require("lvim-lsp.ui.info")
local ui_progress = require("lvim-lsp.ui.progress")
local ui_lightbulb = require("lvim-lsp.ui.lightbulb")
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
---@param opts? table  the merged lvim-lsp + engine config (UI keys split out in setup)
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
        lightbulb = true,
        outline = true,
        footers = true,
        footer_separator = true,
        filters = true,
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
    features.setup_semantic_tokens()
    ls_progress.setup()
    ui_progress.setup()
    ui_lightbulb.setup()
    commands.setup()

    -- Self-register the outline's filetype for cursor hiding — a PERSISTENT side panel (hide the cursor ONLY
    -- while it is the current window). `cursor.register` extends the registry at runtime without rebuilding the
    -- autocmds, so installing lvim-lsp needs no entry in the central cursor config, in any load order.
    pcall(function()
        require("lvim-utils.cursor").register({ panel_ft = { "lvim-lsp-outline" } })
    end)

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

--- Runtime-register a language whose server config a plugin ships itself (e.g. lvim-lang):
--- merges the file_types `entry`, adds the server-config `dir_prefix`, and attaches to
--- already-open buffers of its filetypes. The additive seam for languages injected AFTER setup.
---@param name       string  server module key (also the require suffix <dir_prefix>.<name>)
---@param entry      table   file_types entry ({ filetypes, lsp = {}, formatters?, linters?, debuggers? })
---@param dir_prefix string  require prefix holding the server-config module
function M.register_language(name, entry, dir_prefix)
    ls_manager.register_language(name, entry, dir_prefix)
end

--- Register an alternative outline SOURCE for a filetype (a push source that feeds the outline
--- panel a richer tree than documentSymbol — e.g. dartls' Flutter Outline via lvim-lang).
---@param ft string
---@param source { attach: fun(bufnr: integer, push: fun(nodes: table[])), detach: fun(bufnr: integer) }
function M.outline_register_source(ft, source)
    require("lvim-lsp.ui.outline").register_source(ft, source)
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

--- Code-action availability at the cursor's last lightbulb probe — for statusline / winbar
--- consumers. `{ count = 0 }` when the buffer is not lightbulb-attached.
---@param bufnr? integer  defaults to the current buffer
---@return { count: integer, preferred: boolean }
function M.get_lightbulb(bufnr)
    return ui_lightbulb.get(bufnr)
end

-- ── Info window ───────────────────────────────────────────────────────────────

--- Open the rich LSP information floating window.
---@return { bufnr: integer, win: integer, close: fun() }|nil
function M.show_info()
    return ui_info.show()
end

-- ── navigation API (keymap-friendly) ──────────────────────────────────────────
-- Each takes `{ native?, layout? }` and resolves backend (our picker/peek vs native) + layout per call,
-- falling back to `config.peek.native` / `config.peek.layout`. Bind directly, e.g.
--   vim.keymap.set("n", "gd", function() require("lvim-lsp").definition() end)
--   vim.keymap.set("n", "gD", function() require("lvim-lsp").definition({ layout = "float" }) end)
local nav_api = require("lvim-lsp.core.api")
for _, name in ipairs({
    "definition",
    "type_definition",
    "declaration",
    "references",
    "implementation",
    "diagnostics",
    "incoming_calls",
    "outgoing_calls",
    "workspace_symbol",
    "document_symbol",
    "hover",
    "outline",
}) do
    M[name] = nav_api[name]
end

return M
