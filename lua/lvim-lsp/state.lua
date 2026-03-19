-- lvim-lsp: shared module state — replaces all _G.lsp_* and _G.LVIM.* globals.
-- All other modules read/write through this table so that no global namespace
-- pollution occurs and the plugin remains composable.
--
---@module "lvim-lsp.state"

---@class LvimLspInfoIconsConfig
---@field server  string|nil
---@field section string|nil
---@field item    string|nil
---@field check   string|nil
---@field mason   string|nil
---@field fold    string|nil
---@field error   string|nil
---@field warn    string|nil
---@field info    string|nil
---@field hint    string|nil

---@class LvimLspInfoConfig
---@field popup_title string              Title line shown at the top of the info window (default: "LSP SERVERS INFORMATION")
---@field icons       LvimLspInfoIconsConfig|nil

---@class LvimLspInstallerPanelConfig
---@field name      string|nil  Header bar text (default: "LSP Installer")
---@field icon      string|nil  Header icon
---@field header_hl string|nil  Highlight group for the header bar

---@class LvimLspInstallerConfig
---@field popup_width          number                       Fraction of editor columns (0–1) or absolute integer (default: 0.3)
---@field done_ttl             integer                      Ms a completed tool stays visible (default: 5000)
---@field popup_title          string                       Title shown inside the installer popup (default: "LSP INSTALLER")
---@field spinner              string[]                     Animation frames cycled during installation (default: braille set)
---@field icon_ok              string                       Icon shown when a tool installs successfully (default: "")
---@field icon_error           string                       Icon shown when a tool installation fails    (default: "")
---@field panel                LvimLspInstallerPanelConfig  Installer progress panel appearance

---@class LvimLspEfmConfig
---@field filetypes  string[]  Filetypes EFM should handle even when no tool config is registered
---@field executable string    EFM binary name used for PATH checks (default: "efm-langserver")

---@class LvimLspCommandsConfig

---@class LvimLspDiagnosticSignsConfig
---@field error string|nil
---@field warn  string|nil
---@field hint  string|nil
---@field info  string|nil

---@class LvimLspDiagnosticsConfig
---@field popup_title     string    Title shown in the floating diagnostics window (default: " Diagnostics")
---@field show_line       fun()|nil  Override for LspShowDiagnosticCurrent (default: vim.diagnostic.open_float)
---@field goto_next       fun()|nil  Override for LspShowDiagnosticNext    (default: vim.diagnostic.jump({ count = 1 }))
---@field goto_prev       fun()|nil  Override for LspShowDiagnosticPrev    (default: vim.diagnostic.jump({ count = -1 }))
---@field virtual_text    boolean|nil
---@field virtual_lines   boolean|nil
---@field underline       boolean|nil
---@field severity_sort   boolean|nil
---@field update_in_insert boolean|nil
---@field signs           LvimLspDiagnosticSignsConfig|nil

---@class LvimLspFeaturesConfig
---@field document_highlight boolean
---@field auto_format         boolean
---@field inlay_hints         boolean

---@class LvimLspCodeLensConfig
---@field enabled boolean

---@class LvimLspFormConfig
---@field after_apply string  "Stay" | "Close"

---@class LvimLspProgressPanelConfig
---@field name      string|nil  Header bar text (default: "LSP Progress")
---@field icon      string|nil  Header icon
---@field header_hl string|nil  Highlight group for the header bar

---@class LvimLspProgressHighlightsConfig
---@field icon       string|nil  Highlight for spinner/done icon (default: "Question")
---@field server     string|nil  Highlight for server name      (default: "Title")
---@field title      string|nil  Highlight for in-progress title (default: "WarningMsg")
---@field done       string|nil  Highlight for done title/icon  (default: "Constant")
---@field message    string|nil  Highlight for message text     (default: "Comment")
---@field percentage string|nil  Highlight for percentage value (default: "Special")

---@class LvimLspProgressConfig
---@field enabled      boolean                           Enable/disable the progress subsystem (default: true)
---@field ignore       string[]                          Server names to suppress (default: {})
---@field done_ttl     integer                      Ms to keep a completed entry visible (default: 2000)
---@field spinner      string[]                     Animation frames cycled during active progress
---@field done_icon    string                       Icon shown when a token completes (default: "✓")
---@field render_limit integer                           Max concurrent entries in the panel (default: 4)
---@field panel        LvimLspProgressPanelConfig        Progress panel header appearance
---@field highlights   LvimLspProgressHighlightsConfig   Per-element highlight groups

---@alias LvimLspTool string | { [1]: string, bin: string }

---@class LvimLspFileTypeEntry
---@field filetypes  string[]
---@field lsp        LvimLspTool[]|nil
---@field formatters LvimLspTool[]|nil
---@field linters    LvimLspTool[]|nil
---@field debuggers  LvimLspTool[]|nil

---@class LvimLspConfig
---@field file_types          table<string, LvimLspFileTypeEntry>  REQUIRED. module_key → entry
---@field server_config_dirs  string[]                  Lua require prefixes searched in order for server configs
---@field efm                 LvimLspEfmConfig
---@field info                LvimLspInfoConfig
---@field installer           LvimLspInstallerConfig
---@field commands            LvimLspCommandsConfig
---@field diagnostics         LvimLspDiagnosticsConfig
---@field features            LvimLspFeaturesConfig
---@field code_lens           LvimLspCodeLensConfig
---@field form                LvimLspFormConfig
---@field popup_global        table
---@field progress            LvimLspProgressConfig
---@field highlights          table<string, table>      nvim_set_hl definitions registered via lvim-utils.highlight
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

--- Dep names that do not exist in the Mason registry.
--- Once a name lands here it is permanently skipped — no re-prompting.
---@type table<string, boolean>
M.not_in_registry = {}

-- ── Default configuration ─────────────────────────────────────────────────────

---@type LvimLspConfig
M.config = vim.deepcopy(require("lvim-lsp.config"))

-- Convenience aliases updated by configure() — avoids deep lookups in hot paths
M.file_types = M.config.file_types
M.efm_filetypes = M.config.efm.filetypes

--- Maps Mason package name → installed binary name for tools that differ.
--- Built from bin fields in file_types entries.
---@type table<string, string>
M.bin_aliases = {}

local function build_bin_aliases(file_types)
	local aliases = {}
	local function scan(list)
		for _, tool in ipairs(list or {}) do
			if type(tool) == "table" and tool[1] and tool.bin then
				aliases[tool[1]] = tool.bin
			end
		end
	end
	for _, entry in pairs(file_types) do
		scan(entry.lsp)
		scan(entry.formatters)
		scan(entry.linters)
		scan(entry.debuggers)
	end
	return aliases
end

M.bin_aliases = build_bin_aliases(M.file_types)

--- Merge user config over defaults and refresh convenience aliases.
---@param user_config LvimLspConfig
function M.configure(user_config)
	M.config = vim.tbl_deep_extend("force", M.config, user_config or {}) --[[@as LvimLspConfig]]
	M.file_types = M.config.file_types
	M.efm_filetypes = M.config.efm.filetypes
	M.bin_aliases = build_bin_aliases(M.file_types)
	require("lvim-lsp.ui").reset()
end

return M
