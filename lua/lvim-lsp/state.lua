-- lvim-lsp: shared module state — replaces all _G.lsp_* and _G.LVIM.* globals.
-- All other modules read/write through this table so that no global namespace
-- pollution occurs and the plugin remains composable.
--
---@module "lvim-lsp.state"

---@class LvimLspInfoConfig
---@field popup_width number  Fraction of editor columns (0–1) or absolute integer (default: 0.8)
---@field popup_title string  Title line shown at the top of the info window (default: "LSP SERVERS INFORMATION")

---@class LvimLspInstallerConfig
---@field popup_width          integer   Floating window column width (default: 80)
---@field hide_installed_delay integer   Seconds a completed tool stays visible (default: 5)
---@field popup_title          string    Title shown inside the installer popup (default: "LSP INSTALLER")

---@class LvimLspEfmConfig
---@field filetypes  string[]  Filetypes EFM should handle even when no tool config is registered
---@field executable string    EFM binary name used for PATH checks (default: "efm-langserver")

---@class LvimLspCommandsConfig

---@class LvimLspDiagnosticsConfig
---@field popup_title string    Title shown in the floating diagnostics window (default: " Diagnostics")
---@field show_line   fun()|nil  Override for LspShowDiagnosticCurrent (default: vim.diagnostic.open_float)
---@field goto_next   fun()|nil  Override for LspShowDiagnosticNext    (default: vim.diagnostic.goto_next)
---@field goto_prev   fun()|nil  Override for LspShowDiagnosticPrev    (default: vim.diagnostic.goto_prev)

---@class LvimLspConfig
---@field file_types          table<string, string[]>   REQUIRED. server_key → filetypes[]
---@field server_config_dirs  string[]                  Lua require prefixes searched in order for server configs
---@field efm                 LvimLspEfmConfig
---@field info                LvimLspInfoConfig
---@field installer           LvimLspInstallerConfig
---@field commands            LvimLspCommandsConfig
---@field diagnostics         LvimLspDiagnosticsConfig
---@field colors              table<string, string>     Color palette passed to highlight groups
---@field on_attach           fun(client:any,bufnr:integer)|nil  Global on_attach called for every server
---@field on_dir_change       fun()|nil                 Called on DirChanged after stop_servers (e.g. fidget clear)
---@field startup_delay_ms    integer                   Defer ms before autocmds fire (default: 100)
---@field dir_change_delay_ms integer                   Defer ms before project-cleanup runs (default: 5000)
---@field dap_local_fn        fun()|nil                 When set, adds :LvimLsp dap subcommand

local M = {}

-- ── LSP lifecycle state ───────────────────────────────────────────────────────

--- Maps server_name → root_dir → client_id; one client reused per project root
---@type table<string, table<string, integer>>
M.clients_by_root = {}

--- Servers the user chose not to install, keyed by filetype then server name.
--- Persisted to disk by core/declined.lua.
---@type table<string, table<string, boolean>>
M.declined_servers = {}

--- Server names disabled globally (across all buffers)
---@type table<string, boolean>
M.disabled_servers = {}

--- Per-buffer server disable overrides: bufnr → server_name → boolean
---@type table<integer, table<string, boolean>>
M.disabled_for_buffer = {}

--- Per-filetype EFM tool configs accumulated from language modules
---@type table<string, table[]>
M.efm_configs = {}

--- True while a Mason installation is in progress
---@type boolean
M.installation_in_progress = false

--- True after setup() has been called at least once
---@type boolean
M.initialized = false

-- ── Default configuration ─────────────────────────────────────────────────────

---@type LvimLspConfig
M.config = vim.deepcopy(require("lvim-lsp.config"))

-- Convenience aliases updated by configure() — avoids deep lookups in hot paths
M.file_types    = M.config.file_types
M.efm_filetypes = M.config.efm.filetypes
M.colors        = M.config.colors

--- Merge user config over defaults and refresh convenience aliases.
---@param user_config LvimLspConfig
function M.configure(user_config)
    M.config        = vim.tbl_deep_extend("force", M.config, user_config or {})
    M.file_types    = M.config.file_types
    M.efm_filetypes = M.config.efm.filetypes
    M.colors        = M.config.colors
    M.initialized   = true
    require("lvim-lsp.ui").reset()
end

return M
