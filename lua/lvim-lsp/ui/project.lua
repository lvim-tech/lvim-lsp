-- lvim-lsp: project settings panel.
-- Opens a tabbed UI with three tabs:
--   Servers   → pick a server → form.open() for per-server settings
--   Filetypes → pick a filetype → editor option form
--   Global    → session-only feature/diagnostic toggles
--
---@module "lvim-lsp.ui.project"

local state = require("lvim-lsp.state")
local project = require("lvim-lsp.core.project")
local notify = require("lvim-lsp.utils.notify")

local M = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────

--- Resolve root_dir from current buffer's LSP clients or cwd.
---@param bufnr integer
---@return string
local function resolve_root(bufnr)
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
		if client.config and client.config.root_dir then
			return client.config.root_dir
		end
	end
	return vim.uv.cwd() or vim.fn.getcwd()
end

--- Load server config module for `server_name`.
---@param server_name string
---@return table|nil
local function load_server_mod(server_name)
	for _, dir in ipairs(state.config.server_config_dirs or {}) do
		local ok, mod = pcall(require, dir .. "." .. server_name)
		if ok and type(mod) == "table" then
			return mod
		end
	end
end

--- Apply settings to a live LSP client via workspace/didChangeConfiguration.
---@param server_name string
---@param bufnr       integer
---@param settings    table
local function notify_client(server_name, bufnr, settings)
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
		if client.name == server_name then
			pcall(function()
				client:notify("workspace/didChangeConfiguration", { settings = settings })
				if client.config then
					client.config.settings = vim.tbl_deep_extend("force", client.config.settings or {}, settings)
				end
			end)
			local mod = load_server_mod(server_name)
			local hook = mod and mod.lsp and mod.lsp.config and mod.lsp.config.on_settings_apply
			if type(hook) == "function" then
				pcall(hook, client, bufnr, client.config and client.config.settings or settings)
			end
			return
		end
	end
	notify(
		"[lvim-lsp] " .. server_name .. " is not running — settings saved but not applied live.",
		vim.log.levels.WARN
	)
end

-- ── Servers tab ───────────────────────────────────────────────────────────────

--- Return the display label for a server: lsp[1] from file_types config, else server_name.
---@param server_name string
---@return string
local function server_display_name(server_name)
	local entry = state.file_types[server_name]
	if entry and entry.lsp and entry.lsp[1] then
		local tool = entry.lsp[1]
		return type(tool) == "table" and tool[1] or tool --[[@as string]]
	end
	return server_name
end

local function project_ui()
	return require("lvim-lsp.ui").get()
end

---@param root_dir string
---@param on_select fun(server_name: string)
---@return table[]  rows
local function build_server_rows(_, root_dir, on_select)
	local server_names = {}
	for key, entry in pairs(state.file_types) do
		if entry.lsp and #entry.lsp > 0 then
			table.insert(server_names, key)
		end
	end
	table.sort(server_names)

	local saved, rest = {}, {}
	for _, name in ipairs(server_names) do
		local data = project.load_server(root_dir, name)
		if not vim.tbl_isempty(data) then
			table.insert(saved, name)
		else
			table.insert(rest, name)
		end
	end

	local function make_row(name)
		local n = name
		local display = server_display_name(name)
		return {
			type = "action",
			name = n,
			label = display,
			run = function(_, close)
				close(false, nil)
				on_select(n)
			end,
		}
	end

	local rows = {}
	for _, name in ipairs(saved) do
		table.insert(rows, make_row(name))
	end
	if #saved > 0 and #rest > 0 then
		table.insert(rows, { type = "spacer", label = "" })
	end
	for _, name in ipairs(rest) do
		table.insert(rows, make_row(name))
	end
	return rows
end

-- ── Formatters / Linters tabs ─────────────────────────────────────────────────

--- Collect tools of the given kind from state.file_types config (zero I/O).
--- Returns saved and rest lists of { name, module_key } entries (sorted alphabetically).
---@param kind     string   "formatters"|"linters"
---@param root_dir string
---@return { name: string, module_key: string }[] saved  Entries with saved config
---@return { name: string, module_key: string }[] rest   Entries without saved config
local function collect_efm_tool_entries(kind, root_dir)
	local seen = {}
	local entries = {}
	for module_key, entry in pairs(state.file_types) do
		for _, tool_name in ipairs(entry[kind] or {}) do
			if not seen[tool_name] then
				seen[tool_name] = true
				table.insert(entries, { name = tool_name, module_key = module_key })
			end
		end
	end
	table.sort(entries, function(a, b)
		return a.name < b.name
	end)

	local saved, rest = {}, {}
	for _, e in ipairs(entries) do
		if not vim.tbl_isempty(project.load_efm_tool(root_dir, e.name)) then
			table.insert(saved, e)
		else
			table.insert(rest, e)
		end
	end
	return saved, rest
end

---@param kind      string  "formatters"|"linters"
---@param root_dir  string
---@param on_select fun(tool_name: string, module_key: string)
---@return table[]
local function build_efm_tool_rows(kind, root_dir, on_select)
	local saved, rest = collect_efm_tool_entries(kind, root_dir)
	if #saved == 0 and #rest == 0 then
		return { { type = "spacer", label = "(none configured)" } }
	end

	local function make_row(e)
		local n = e.name
		local mk = e.module_key
		return {
			type = "action",
			name = n,
			label = n,
			run = function(_, close)
				close(false, nil)
				on_select(n, mk)
			end,
		}
	end

	local rows = {}
	for _, e in ipairs(saved) do
		table.insert(rows, make_row(e))
	end
	if #saved > 0 and #rest > 0 then
		table.insert(rows, { type = "spacer", label = "" })
	end
	for _, e in ipairs(rest) do
		table.insert(rows, make_row(e))
	end
	return rows
end

--- Open a form for a single EFM tool.
--- Loads the module lazily (only on click) to get the default command.
---@param tool_name  string
---@param module_key string  Used to lazy-load the module file for default_cmd
---@param root_dir   string
---@param on_back?   fun()
local function open_efm_tool_form(tool_name, module_key, root_dir, on_back)
	local ui_mod = require("lvim-lsp.ui").get()
	if not ui_mod then
		return
	end

	-- Lazy load: read default command from the module file, only now.
	local default_cmd = ""
	for _, dir in ipairs(state.config.server_config_dirs) do
		local ok, mod = pcall(require, dir .. "." .. module_key)
		if ok and type(mod) == "table" and mod.efm and mod.efm.tools then
			for _, tool in ipairs(mod.efm.tools) do
				if tool.server_name == tool_name then
					default_cmd = tool.formatCommand or tool.lintCommand or ""
					break
				end
			end
			break
		end
	end

	local proj = require("lvim-lsp.core.project")
	local saved = proj.load_efm_tool(root_dir, tool_name)
	local pending = vim.deepcopy(saved)
	local keys_cfg = state.config.popup_global and state.config.popup_global.keys or {}
	local back_key = keys_cfg.back or "u"
	local after_apply_def = state.config.form and state.config.form.after_apply or "Stay"
	local stay = { value = after_apply_def == "Stay" }

	local rows = {
		{
			type = "bool",
			name = "enabled",
			label = "Enabled",
			value = saved.enabled ~= false,
			run = function(v)
				pending.enabled = v
			end,
		},
		{
			type = "string",
			name = "command",
			label = "Command Override",
			value = saved.command or default_cmd,
			run = function(v)
				pending.command = (v ~= "" and v ~= default_cmd) and v or nil
			end,
		},
		{ type = "spacer_line" },
		{
			type = "select",
			name = "_after_apply",
			label = "After Apply",
			value = after_apply_def,
			options = { "Stay", "Close" },
			run = function(val)
				stay.value = (val == "Stay")
			end,
		},
		{ type = "spacer", label = "" },
		{
			type = "action",
			label = "Apply for session",
			run = function(_, close)
				proj.apply_efm_tool_session(root_dir, tool_name, pending)
				local manager = require("lvim-lsp.core.manager")
				for _, c in ipairs(vim.lsp.get_clients()) do
					if c.name == "efm" then
						pcall(c.stop, c)
						break
					end
				end
				vim.defer_fn(function()
					manager.start_language_server("efm", true)
				end, 200)
				if not stay.value then
					close(true, pending)
				end
			end,
		},
		{
			type = "action",
			label = "Apply permanently",
			run = function(_, close)
				proj.save_efm_tool(root_dir, tool_name, pending)
				proj.invalidate_efm_tool(root_dir, tool_name)
				local manager = require("lvim-lsp.core.manager")
				for _, c in ipairs(vim.lsp.get_clients()) do
					if c.name == "efm" then
						pcall(c.stop, c)
						break
					end
				end
				vim.defer_fn(function()
					manager.start_language_server("efm", true)
				end, 200)
				notify("[lvim-lsp] " .. tool_name .. " settings saved.", vim.log.levels.INFO)
				if not stay.value then
					close(true, pending)
				end
			end,
		},
	}

	ui_mod.tabs({
		title = tool_name .. " — Settings",
		tabs = { { label = "Options", rows = rows } },
		back_key = on_back and back_key or nil,
		on_open = on_back
				and function(buf, _)
					vim.keymap.set("n", back_key, function()
						vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("q", true, false, true), "m", false)
					end, { buffer = buf, silent = true, nowait = true })
				end
			or nil,
		callback = on_back and function(confirmed, _)
			if not confirmed then
				on_back()
			end
		end or nil,
	})
end

-- ── Filetypes tab ─────────────────────────────────────────────────────────────

---@param on_select fun(ft: string)
---@return table[]  rows
local function build_ft_rows(root_dir, on_select)
	local ft_set = {}
	for _, entry in pairs(state.file_types) do
		for _, ft in ipairs(entry.filetypes or {}) do
			ft_set[ft] = true
		end
	end
	for ft in pairs(state.efm_configs) do
		ft_set[ft] = true
	end
	for _, ft in ipairs(state.efm_filetypes) do
		ft_set[ft] = true
	end
	local fts = vim.tbl_keys(ft_set)
	table.sort(fts)

	local saved, rest = {}, {}
	for _, ft in ipairs(fts) do
		local data = project.load_ft(root_dir, ft)
		if not vim.tbl_isempty(data) then
			table.insert(saved, ft)
		else
			table.insert(rest, ft)
		end
	end

	local function make_row(ft)
		local f = ft
		return {
			type = "action",
			name = f,
			label = f,
			run = function(_, close)
				close(false, nil)
				on_select(f)
			end,
		}
	end

	local rows = {}
	for _, ft in ipairs(saved) do
		table.insert(rows, make_row(ft))
	end
	if #saved > 0 and #rest > 0 then
		table.insert(rows, { type = "spacer", label = "" })
	end
	for _, ft in ipairs(rest) do
		table.insert(rows, make_row(ft))
	end
	return rows
end

--- vim buffer options shown per-filetype.
local FT_OPTIONS = {
	-- Indentation
	{ key = "tabstop", type = "int", label = "Tab Stop" },
	{ key = "shiftwidth", type = "int", label = "Shift Width" },
	{ key = "softtabstop", type = "int", label = "Soft Tab Stop" },
	{ key = "expandtab", type = "bool", label = "Expand Tab" },
	{ key = "smartindent", type = "bool", label = "Smart Indent" },
	{ key = "autoindent", type = "bool", label = "Auto Indent" },
	-- View
	{ key = "relativenumber", type = "bool", label = "Show Relative Line Numbers" },
	{ key = "cursorline", type = "bool", label = "Show Cursor Line" },
	{ key = "cursorcolumn", type = "bool", label = "Show Cursor Column" },
	{ key = "wrap", type = "bool", label = "Wrap Lines" },
	{
		key = "colorcolumn",
		type = "string",
		label = "Color Column",
		normalize = function(v)
			if type(v) == "table" then
				return table.concat(v, ",")
			end
			return tostring(v or "")
		end,
	},
	-- Lines
	{ key = "textwidth", type = "int", label = "Text Width" },
	{ key = "linebreak", type = "bool", label = "Line Break" },
	{ key = "breakindent", type = "bool", label = "Break Indent" },
	-- Folding
	{
		key = "foldmethod",
		type = "select",
		label = "Fold Method",
		options = { "manual", "indent", "expr", "marker", "syntax", "diff" },
	},
	{ key = "foldlevel", type = "int", label = "Fold Level" },
	-- Comments / formatting
	{ key = "formatoptions", type = "string", label = "Format Options" },
	{ key = "comments", type = "string", label = "Comments" },
	{ key = "commentstring", type = "string", label = "Comment String" },
	-- Completion
	{ key = "omnifunc", type = "string", label = "Omni Func" },
	{ key = "complete", type = "string", label = "Complete" },
	-- Spell
	{ key = "spell", type = "bool", label = "Spell Check" },
	{ key = "spelllang", type = "string", label = "Spell Lang" },
	-- Misc
	{
		key = "conceallevel",
		type = "select",
		label = "Conceal Level",
		options = { "0", "1", "2", "3" },
		int_select = true,
	},
	{
		key = "concealcursor",
		type = "select",
		label = "Conceal Cursor",
		options = { "", "n", "v", "i", "c", "nv", "ni", "nc", "nvi", "nvic" },
	},
	{ key = "modeline", type = "bool", label = "Modeline" },
	{ key = "fixendofline", type = "bool", label = "Fix End of Line" },
	{ key = "endofline", type = "bool", label = "End of Line" },
	{ key = "fileformat", type = "select", label = "File Format", options = { "unix", "dos", "mac" } },
	{
		key = "fileencoding",
		type = "select",
		label = "File Encoding",
		options = { "utf-8", "utf-16", "utf-16le", "utf-16be", "latin1", "cp1251", "cp1252", "iso-8859-1" },
	},
}

--- Open per-filetype editor options form.
---@param ft       string
---@param root_dir string
---@param bufnr    integer
---@param on_back? fun()
local function open_ft_form(ft, root_dir, bufnr, on_back)
	local ui_mod = require("lvim-lsp.ui").get()
	if not ui_mod then
		return
	end

	local saved = project.load_ft(root_dir, ft)
	local pending = vim.deepcopy(saved)

	-- Read current option as fallback when no saved value (bo then wo)
	local win = vim.fn.bufwinid(bufnr)
	local function cur(key)
		if pending[key] ~= nil then
			return pending[key]
		end
		local ok, val = pcall(function()
			return vim.bo[bufnr][key]
		end)
		if ok and val ~= nil then
			return val
		end
		if win ~= -1 then
			ok, val = pcall(function()
				return vim.wo[win][key]
			end)
			if ok and val ~= nil then
				return val
			end
		end
		return nil
	end

	local keys_cfg = state.config.popup_global and state.config.popup_global.keys or {}
	local back_key = keys_cfg.back or "u"
	local after_apply_def = state.config.form and state.config.form.after_apply or "Stay"
	local stay = { value = after_apply_def == "Stay" }
	local rows = {}
	for _, opt in ipairs(FT_OPTIONS) do
		local t = opt.type == "int" and "int"
			or opt.type == "bool" and "bool"
			or opt.type == "select" and "select"
			or "string"
		table.insert(rows, {
			type = t,
			name = opt.key,
			label = opt.label,
			value = opt.normalize and opt.normalize(cur(opt.key))
				or (opt.int_select and tostring(cur(opt.key) or "") or cur(opt.key)),
			options = opt.options,
			run = function(val)
				pending[opt.key] = opt.int_select and tonumber(val) or val
			end,
		})
	end

	table.insert(rows, { type = "spacer_line" })
	table.insert(rows, {
		type = "select",
		name = "_after_apply",
		label = "After Apply",
		value = after_apply_def,
		options = { "Stay", "Close" },
		run = function(val)
			stay.value = (val == "Stay")
		end,
	})
	table.insert(rows, { type = "spacer", label = "" })
	local function apply_opts()
		for k, v in pairs(pending) do
			pcall(function()
				vim.bo[bufnr][k] = v
			end)
			if win ~= -1 then
				pcall(function()
					vim.wo[win][k] = v
				end)
			end
		end
	end
	table.insert(rows, {
		type = "action",
		label = "Apply for session",
		run = function(_, close)
			apply_opts()
			if not stay.value then
				close(true, pending)
			end
		end,
	})
	table.insert(rows, {
		type = "action",
		label = "Apply permanently",
		run = function(_, close)
			apply_opts()
			project.save_ft(root_dir, ft, pending)
			project.invalidate_ft(root_dir, ft)
			if not stay.value then
				close(true, pending)
			end
		end,
	})

	ui_mod.tabs({
		title = ft .. " — Editor Options",
		tabs = { { label = "Options", rows = rows } },
		back_key = on_back and back_key or nil,
		on_open = on_back
				and function(buf, _)
					vim.keymap.set("n", back_key, function()
						vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("q", true, false, true), "m", false)
					end, { buffer = buf, silent = true, nowait = true })
				end
			or nil,
		callback = on_back and function(confirmed, _)
			if not confirmed then
				on_back()
			end
		end or nil,
	})
end

-- ── Restart LSP submenu ───────────────────────────────────────────────────────

local function open_restart_form(on_back)
	local ui_mod = require("lvim-lsp.ui").get()
	if not ui_mod then
		return
	end
	local manager = require("lvim-lsp.core.manager")
	local cfg = state.config

	local seen, names = {}, {}
	for _, client in ipairs(vim.lsp.get_clients()) do
		if not seen[client.name] then
			seen[client.name] = true
			table.insert(names, client.name)
		end
	end
	if #names == 0 then
		notify("[lvim-lsp] No active LSP servers.", vim.log.levels.WARN)
		return
	end
	table.sort(names)

	local keys_cfg = cfg.popup_global and cfg.popup_global.keys or {}
	local back_key = keys_cfg.back or "u"
	local after_apply_def = cfg.form and cfg.form.after_apply or "Stay"
	local stay = { value = after_apply_def == "Stay" }

	local selected = {}
	for _, name in ipairs(names) do
		selected[name] = false
	end

	local rows = {}
	for _, name in ipairs(names) do
		table.insert(rows, {
			type = "bool",
			name = name,
			label = name,
			value = false,
			run = function(v)
				selected[name] = v
			end,
		})
	end
	table.insert(rows, { type = "spacer_line" })
	table.insert(rows, {
		type = "select",
		name = "_after_apply",
		label = "After Restart",
		value = after_apply_def,
		options = { "Stay", "Close" },
		run = function(val)
			stay.value = (val == "Stay")
		end,
	})
	table.insert(rows, { type = "spacer", label = "" })
	table.insert(rows, {
		type = "action",
		label = "Restart Selected",
		run = function(_, close)
			local to_restart = {}
			for name, checked in pairs(selected) do
				if checked then
					table.insert(to_restart, name)
				end
			end
			if #to_restart == 0 then
				notify("[lvim-lsp] No servers selected.", vim.log.levels.WARN)
				return
			end
			table.sort(to_restart)
			for _, name in ipairs(to_restart) do
				for _, client in ipairs(vim.lsp.get_clients({ name = name })) do
					pcall(client.stop, client)
				end
				vim.defer_fn(function()
					manager.start_language_server(name, true)
				end, 500)
			end
			notify("[lvim-lsp] Restarting: " .. table.concat(to_restart, ", "), vim.log.levels.INFO)
			if not stay.value then
				close(true, selected)
			end
		end,
	})

	ui_mod.tabs({
		title = "Restart LSP Servers",
		back_key = on_back and back_key or nil,
		on_open = on_back
				and function(buf, _)
					vim.keymap.set("n", back_key, function()
						vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("q", true, false, true), "m", false)
					end, { buffer = buf, silent = true, nowait = true })
				end
			or nil,
		callback = on_back and function(confirmed, _)
			if not confirmed then
				on_back()
			end
		end or nil,
		tabs = {
			{ label = "Servers", rows = rows },
		},
	})
end

-- ── Global tab ────────────────────────────────────────────────────────────────

---@return table  rows
local function build_global_rows(root_dir, on_info_back, on_restart_back)
	local cfg = state.config
	local after_apply_def = cfg.form and cfg.form.after_apply or "Stay"
	local stay = { value = after_apply_def == "Stay" }
	local pending = {
		features = vim.deepcopy(cfg.features),
		code_lens = vim.deepcopy(cfg.code_lens),
		diagnostics = vim.deepcopy(cfg.diagnostics),
		progress = cfg.progress and cfg.progress.enabled ~= false,
	}
	local features_mod = require("lvim-lsp.core.features")

	local function apply_pending()
		state.config.features = vim.tbl_deep_extend("force", cfg.features, pending.features)
		state.config.code_lens = vim.tbl_deep_extend("force", cfg.code_lens, pending.code_lens)
		state.config.diagnostics = vim.tbl_deep_extend("force", cfg.diagnostics, pending.diagnostics)
		state.config.progress.enabled = pending.progress
		require("lvim-lsp.core.progress").suppress(not pending.progress)
		features_mod.setup_diagnostics()
		features_mod.setup_code_lens()
	end

	local function apply_permanent()
		apply_pending()
		require("lvim-lsp.core.globals").save({
			auto_format = pending.features.auto_format,
			inlay_hints = pending.features.inlay_hints,
			document_highlight = pending.features.document_highlight,
			code_lens = pending.code_lens.enabled,
			progress = pending.progress,
			virtual_text = pending.diagnostics.virtual_text and true or false,
			virtual_lines = pending.diagnostics.virtual_lines and true or false,
			underline = pending.diagnostics.underline,
			severity_sort = pending.diagnostics.severity_sort,
			update_in_insert = pending.diagnostics.update_in_insert,
		})
		notify("[lvim-lsp] Global settings saved.", vim.log.levels.INFO)
	end

	local rows = {
		{ type = "spacer", label = "Features" },
		{
			type = "bool",
			name = "document_highlight",
			label = "Document Highlight",
			value = cfg.features.document_highlight,
			run = function(v)
				pending.features.document_highlight = v
			end,
		},
		{
			type = "bool",
			name = "auto_format",
			label = "Auto Format on Save",
			value = cfg.features.auto_format,
			run = function(v)
				pending.features.auto_format = v
			end,
		},
		{
			type = "bool",
			name = "inlay_hints",
			label = "Inlay Hints",
			value = cfg.features.inlay_hints,
			run = function(v)
				pending.features.inlay_hints = v
			end,
		},

		{ type = "spacer", label = "Code Lens" },
		{
			type = "bool",
			name = "code_lens_enabled",
			label = "Enabled",
			value = cfg.code_lens.enabled,
			run = function(v)
				pending.code_lens.enabled = v
			end,
		},

		{ type = "spacer", label = "Diagnostics" },
		{
			type = "select",
			name = "virtual_diagnostic",
			label = "Virtual Diagnostic",
			value = cfg.diagnostics.virtual_lines and "virtual_lines"
				or cfg.diagnostics.virtual_text and "virtual_text"
				or "none",
			options = { "none", "virtual_text", "virtual_lines" },
			run = function(v)
				pending.diagnostics.virtual_text = (v == "virtual_text")
				pending.diagnostics.virtual_lines = (v == "virtual_lines")
			end,
		},
		{
			type = "bool",
			name = "underline",
			label = "Underline",
			value = cfg.diagnostics.underline,
			run = function(v)
				pending.diagnostics.underline = v
			end,
		},
		{
			type = "bool",
			name = "severity_sort",
			label = "Severity Sort",
			value = cfg.diagnostics.severity_sort,
			run = function(v)
				pending.diagnostics.severity_sort = v
			end,
		},
		{
			type = "bool",
			name = "update_in_insert",
			label = "Update in Insert Mode",
			value = cfg.diagnostics.update_in_insert,
			run = function(v)
				pending.diagnostics.update_in_insert = v
			end,
		},

		{ type = "spacer", label = "Progress" },
		{
			type = "bool",
			name = "progress_enabled",
			label = "LSP Progress",
			value = cfg.progress and cfg.progress.enabled ~= false,
			run = function(v)
				pending.progress = v
			end,
		},

		{ type = "spacer_line" },
		{
			type = "select",
			name = "_after_apply",
			label = "After Apply",
			value = after_apply_def,
			options = { "Stay", "Close" },
			run = function(val)
				stay.value = (val == "Stay")
			end,
		},
		{ type = "spacer", label = "" },
		{
			type = "action",
			label = "Apply for session",
			run = function(_, close)
				apply_pending()
				if not stay.value then
					close(true, pending)
				end
			end,
		},
		{
			type = "action",
			label = "Apply permanently",
			run = function(_, close)
				apply_permanent()
				if not stay.value then
					close(true, pending)
				end
			end,
		},
		{ type = "spacer_line" },
		{
			type = "action",
			name = "Info LSP",
			label = "Info LSP",
			run = function(_, close)
				close(false, nil)
				require("lvim-lsp.ui.info").show(on_info_back)
			end,
		},
		{
			type = "action",
			name = "Restart LSP",
			label = "Restart LSP",
			run = function(_, close)
				close(false, nil)
				open_restart_form(on_restart_back)
			end,
		},
	}

	return rows
end

-- ── Public: open ──────────────────────────────────────────────────────────────

--- Open the project settings panel for the current buffer.
---@param bufnr        integer
---@param tab_selector integer|nil         Re-open on this tab index (used by on_back)
---@param initial_row  string|integer|nil  Re-position cursor on this row name/index
---@return nil
function M.open(bufnr, tab_selector, initial_row)
	local ui_mod = project_ui()
	if not ui_mod then
		notify("lvim-lsp: lvim-utils is required", vim.log.levels.ERROR)
		return
	end

	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local root_dir = resolve_root(bufnr)

	local function back(tab, row)
		M.open(bufnr, tab, row)
	end

	local server_rows = build_server_rows(bufnr, root_dir, function(server_name)
		local form = require("lvim-lsp.ui.form")
		form.open(server_name, root_dir, bufnr, function(settings)
			notify_client(server_name, bufnr, settings)
		end, function(delta, full)
			local ok = project.save_server(root_dir, server_name, { settings = delta })
			project.invalidate_server(root_dir, server_name)
			if ok then
				notify_client(server_name, bufnr, full)
				notify("[lvim-lsp] " .. server_name .. " settings saved.", vim.log.levels.INFO)
			else
				notify("[lvim-lsp] failed to save settings for " .. server_name, vim.log.levels.ERROR)
			end
		end, function()
			back(1, server_name)
		end)
	end)

	local formatter_rows = build_efm_tool_rows("formatters", root_dir, function(tool_name, module_key)
		open_efm_tool_form(tool_name, module_key, root_dir, function()
			back(2, tool_name)
		end)
	end)

	local linter_rows = build_efm_tool_rows("linters", root_dir, function(tool_name, module_key)
		open_efm_tool_form(tool_name, module_key, root_dir, function()
			back(3, tool_name)
		end)
	end)

	local ft_rows = build_ft_rows(root_dir, function(ft)
		open_ft_form(ft, root_dir, bufnr, function()
			back(4, ft)
		end)
	end)

	local global_rows = build_global_rows(root_dir, function()
		back(5, "Info LSP")
	end, function()
		back(5, "Restart LSP")
	end)

	local proj_cfg = state.config.project or {}
	local tabs_cfg = proj_cfg.tabs or {}
	local title_icon = proj_cfg.title_icon and (proj_cfg.title_icon .. " ") or ""

	local function tab_spec(key, default_label, rows)
		local tc = tabs_cfg[key] or {}
		return { label = tc.label or default_label, icon = tc.icon, rows = rows }
	end

	ui_mod.tabs({
		title = title_icon .. "Project — " .. vim.fn.fnamemodify(root_dir, ":t"),
		tab_selector = tab_selector,
		initial_row = initial_row,
		tabs = {
			tab_spec("servers", "LSP Servers", server_rows),
			tab_spec("formatters", "Formatters", formatter_rows),
			tab_spec("linters", "Linters", linter_rows),
			tab_spec("filetypes", "Filetypes", ft_rows),
			tab_spec("global", "Global", global_rows),
		},
	})
end

return M
