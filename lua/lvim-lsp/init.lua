-- lvim-lsp: public API entry point.
-- Call require("lvim-lsp").setup(opts) once in your config.
-- All other public functions are re-exported here so callers never need to
-- reach into sub-modules directly.
--
---@module "lvim-lsp"

local M = {}

--- Configure and activate the LSP manager.
--- Must be called before any other function in this module.
---@param opts LvimLspConfig
function M.setup(opts)
    local state      = require("lvim-lsp.state")
    local highlights = require("lvim-lsp.ui.highlights")
    local commands   = require("lvim-lsp.core.commands")
    local bootstrap  = require("lvim-lsp.core.bootstrap")
    require("lvim-lsp.core.declined").load()

    local features = require("lvim-lsp.core.features")

    state.configure(opts or {})
    highlights.setup(state.colors)
    features.setup_diagnostics()
    features.setup_code_lens()
    commands.setup()
    bootstrap.init()
end

-- ── Re-exports (installer) ────────────────────────────────────────────────────

--- Ensures Mason packages are installed; fires `cb` when done.
---@param tools string[]
---@param cb    function|nil
function M.ensure_mason_tools(tools, cb)
    require("lvim-lsp.ui.installer").ensure_mason_tools(tools, cb)
end

--- Print a debug summary of the current installer state.
function M.installer_status()
    require("lvim-lsp.ui.installer").status()
end

-- ── Re-exports (manager) ──────────────────────────────────────────────────────

--- Start or attach an LSP server to a buffer.
---@param server_name string
---@param bufnr       integer
---@return integer|nil
function M.ensure_lsp_for_buffer(server_name, bufnr)
    return require("lvim-lsp.core.manager").ensure_lsp_for_buffer(server_name, bufnr)
end

--- Register EFM tool configs and restart EFM.
---@param filetypes    string[]
---@param tools_config table[]
function M.setup_efm(filetypes, tools_config)
    require("lvim-lsp.core.manager").setup_efm(filetypes, tools_config)
end

--- Start an LSP server (optionally force-attach to all compatible buffers).
---@param server_name string
---@param force       boolean
---@return integer|nil
function M.start_language_server(server_name, force)
    return require("lvim-lsp.core.manager").start_language_server(server_name, force)
end

--- Disable a server globally (stops all running instances).
---@param server_name string
function M.disable_lsp_server_globally(server_name)
    require("lvim-lsp.core.manager").disable_lsp_server_globally(server_name)
end

--- Re-enable a previously disabled server globally.
---@param server_name string
function M.enable_lsp_server_globally(server_name)
    require("lvim-lsp.core.manager").enable_lsp_server_globally(server_name)
end

--- Disable a server for a single buffer.
---@param server_name string
---@param bufnr       integer
function M.disable_lsp_server_for_buffer(server_name, bufnr)
    require("lvim-lsp.core.manager").disable_lsp_server_for_buffer(server_name, bufnr)
end

--- Re-enable a server for a single buffer and immediately re-attach.
---@param server_name string
---@param bufnr       integer
function M.enable_lsp_server_for_buffer(server_name, bufnr)
    require("lvim-lsp.core.manager").enable_lsp_server_for_buffer(server_name, bufnr)
end

--- Returns all server names compatible with filetype `ft`.
---@param ft string
---@return string[]
function M.get_compatible_lsp_for_ft(ft)
    return require("lvim-lsp.core.manager").get_compatible_lsp_for_ft(ft)
end

--- Returns a read-only snapshot of module state (useful for debugging).
---@return table
function M.get_state()
    local state = require("lvim-lsp.state")
    return vim.deepcopy({
        clients_by_root        = state.clients_by_root,
        disabled_servers       = state.disabled_servers,
        disabled_for_buffer    = state.disabled_for_buffer,
        efm_configs            = state.efm_configs,
        installation_in_progress = state.installation_in_progress,
        config                 = state.config,
    })
end

-- ── Info window ───────────────────────────────────────────────────────────────

--- Open the rich LSP information floating window.
---@return { bufnr: integer, win: integer, close: fun() }|nil
function M.show_info()
    return require("lvim-lsp.ui.info").show()
end

-- ── Highlights ────────────────────────────────────────────────────────────────

--- Re-run highlight setup (call after a colorscheme change).
function M.refresh_highlights()
    local highlights = require("lvim-lsp.ui.highlights")
    local state      = require("lvim-lsp.state")
    highlights.reset()
    highlights.setup(state.colors)
end

return M
