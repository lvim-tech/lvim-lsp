-- lvim-lsp: info — rich LSP information floating window.
-- Shows active clients, capabilities, diagnostics, workspace, trigger chars,
-- Mason package info and EFM linters/formatters.
-- Requires lvim-utils for the floating window.
--
---@module "lvim-lsp.info"

local state = require("lvim-lsp.state")

local M = {}

-- ── Icons / indent constants ───────────────────────────────────────────────────

local function get_icons()
	local cfg = state.config.info and state.config.info.icons or {}
	return {
		square  = cfg.server,
		diamond = cfg.section,
		circle  = cfg.item,
		cross   = cfg.error,
		check   = cfg.check,
		warn    = cfg.warn,
		info    = cfg.info,
		hint    = cfg.hint,
		mason   = cfg.mason,
		fold    = cfg.fold,
	}
end

local L0 = ""
local L1 = "  "
local L2 = "    "
local L3 = "      "

-- ── Private helpers ────────────────────────────────────────────────────────────

local function sanitize(s)
	return tostring(s):gsub("[\n\r]", " ")
end

local function format_value(val)
	if type(val) == "string" then return '"' .. sanitize(val) .. '"' end
	if type(val) == "function" then return "<function>" end
	if val == nil then return "nil" end
	return sanitize(val)
end

-- ── Content builders ──────────────────────────────────────────────────────────

local function make_builders()
	local lines      = {}
	local highlights = {}
	local folds      = {}

	local function add_hl(line_idx, substr, group)
		local text = lines[line_idx + 1]
		local s, e = string.find(text, substr, 1, true)
		if s and e then
			table.insert(highlights, { line = line_idx, col_start = s - 1, col_end = e, group = group })
		end
	end

	local function add_icon_hl(line_idx, icon)
		add_hl(line_idx, icon, "LvimLspIcon")
	end

	local function add_sep(popup_width, group)
		table.insert(lines, string.rep("─", popup_width))
		table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = -1, group = group or "LvimLspInfoSeparator" })
	end

	local function add_section(icon, label, hl_group)
		table.insert(lines, "")
		table.insert(lines, L1 .. icon .. " " .. label)
		add_hl(#lines - 1, label, hl_group or "LvimLspInfoSection")
		add_icon_hl(#lines - 1, icon)
	end

	--- Recursively render a settings table, creating a fold for each nested subtable.
	--- line indices are 0-based to match the buffer.
	local function render_settings(tbl, indent)
		local keys = {}
		for k in pairs(tbl) do table.insert(keys, k) end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for _, k in ipairs(keys) do
			local v  = tbl[k]
			local ks = tostring(k)
			if type(v) == "table" then
				local fold_start = #lines  -- 0-based index of this header line
				table.insert(lines, indent .. ks .. ":")
				add_hl(#lines - 1, ks, "LvimLspInfoKey")
				if next(v) ~= nil then
					render_settings(v, indent .. "  ")
					local fold_end = #lines - 1
					if fold_end > fold_start then
						table.insert(folds, { start_line = fold_start, end_line = fold_end })
					end
				end
			else
				table.insert(lines, indent .. ks .. ": " .. format_value(v))
				add_hl(#lines - 1, ks .. ":", "LvimLspInfoKey")
			end
		end
	end

	return lines, highlights, folds, add_hl, add_icon_hl, add_sep, add_section, render_settings
end

-- ── Diagnostic helpers ─────────────────────────────────────────────────────────

local function client_diag_counts(client_id, bufnr)
	local sev    = vim.diagnostic.severity
	local counts = { [sev.ERROR] = 0, [sev.WARN] = 0, [sev.INFO] = 0, [sev.HINT] = 0 }
	local ns_ok, ns = pcall(vim.lsp.diagnostic.get_namespace, client_id)
	if not ns_ok then return counts end
	local diags = bufnr
		and vim.diagnostic.get(bufnr, { namespace = ns })
		or  vim.diagnostic.get(nil,   { namespace = ns })
	for _, d in ipairs(diags) do
		counts[d.severity] = (counts[d.severity] or 0) + 1
	end
	return counts
end

local function diag_summary(counts, icons)
	local sev = vim.diagnostic.severity
	return string.format(
		"%s %d  %s %d  %s %d  %s %d",
		icons.cross, counts[sev.ERROR],
		icons.warn,  counts[sev.WARN],
		icons.info,  counts[sev.INFO],
		icons.hint,  counts[sev.HINT]
	)
end

-- ── Mason helper ───────────────────────────────────────────────────────────────

--- Returns Mason package info for all deps of `server_name`.
--- Loads the server config module to resolve actual package names (e.g. "lua" → "lua-language-server").
local function mason_info(server_name)
	local ok, reg = pcall(require, "mason-registry")
	if not ok then return {} end

	-- Collect dep names from the server config module
	local deps = {}
	for _, dir in ipairs(state.config.server_config_dirs) do
		local m_ok, mod = pcall(require, dir .. "." .. server_name)
		if m_ok and type(mod) == "table" then
			if mod.lsp and mod.lsp.dependencies then
				for _, d in ipairs(mod.lsp.dependencies) do table.insert(deps, d) end
			end
			if mod.efm then
				table.insert(deps, "efm-langserver")
				if mod.efm.dependencies then
					for _, d in ipairs(mod.efm.dependencies) do table.insert(deps, d) end
				end
			end
			if mod.dap and mod.dap.dependencies then
				for _, d in ipairs(mod.dap.dependencies) do table.insert(deps, d) end
			end
			break
		end
	end

	-- Fall back to exact server name + underscore→hyphen variant
	if #deps == 0 then
		deps = { server_name, server_name:gsub("_", "-") }
	end

	local results = {}
	local seen    = {}
	for _, dep in ipairs(deps) do
		-- Resolve Mason package name (e.g. "efm-langserver" → "efm")
		local installer_ok, installer = pcall(require, "lvim-lsp.ui.installer")
		local pkg_name = installer_ok and installer.pkg_name and installer.pkg_name(dep) or dep
		if not seen[pkg_name] then
			seen[pkg_name] = true
			local p_ok, pkg = pcall(reg.get_package, pkg_name)
			if p_ok and pkg then
				local i_ok, installed = pcall(function() return pkg:is_installed() end)
				if i_ok and installed then
					local v_ok, ver = pcall(function() return pkg:get_installed_version() end)
					table.insert(results, { name = pkg.name, version = v_ok and sanitize(ver) or "?" })
				end
			end
		end
	end
	return results
end

-- ── Process PID ───────────────────────────────────────────────────────────────

local function client_pid(client)
	local ok, pid = pcall(function()
		return client.rpc and client.rpc.handle and client.rpc.handle:get_pid()
	end)
	return ok and pid or nil
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Open the rich LSP information window.
---@param on_back? fun()  Called when user presses the back key to return to the parent panel.
---@return { bufnr: integer, win: integer, close: fun() }|nil
function M.show(on_back)
	local clients = vim.lsp.get_clients()
	if #clients == 0 then
		vim.notify("No active LSP clients found", vim.log.levels.INFO)
		return
	end

	local ICONS = get_icons()
	local pg = state.config.popup_global
	local popup_width = require("lvim-lsp.ui").resolve_width(pg.width or 0.8, math.floor(vim.o.columns * 0.8))

	local lines, highlights, folds, add_hl, add_icon_hl, add_sep, add_section, render_settings = make_builders()

	-- ── Sort clients: EFM first ───────────────────────────────────────────────

	local efm_client, other_clients = nil, {}
	for _, client in ipairs(clients) do
		if client.name == "efm" then efm_client = client
		else table.insert(other_clients, client) end
	end
	local sorted = {}
	if efm_client then table.insert(sorted, efm_client) end
	for _, c in ipairs(other_clients) do table.insert(sorted, c) end

	-- ── Per-client sections ───────────────────────────────────────────────────

	for _, client in ipairs(sorted) do
		table.insert(lines, "")
		table.insert(lines, L0 .. ICONS.square .. " " .. client.name .. "  (ID: " .. client.id .. ")")
		add_hl(#lines - 1, client.name, "LvimLspInfoServerName")
		add_icon_hl(#lines - 1, ICONS.square)

		-- ── EFM: linters / formatters ─────────────────────────────────────────
		if client.name == "efm" then
			local enc = client.offset_encoding or "?"
			local pid = client_pid(client)
			local pid_str = pid and ("  │  PID: " .. pid) or ""
			table.insert(lines, L1 .. "Encoding: " .. enc .. pid_str)
			add_hl(#lines - 1, "Encoding:", "LvimLspInfoKey")
			if pid then add_hl(#lines - 1, "PID:", "LvimLspInfoKey") end

			-- Build filetype → buffers map
			local bufs_by_ft = {}
			if client.attached_buffers then
				for bufnr in pairs(client.attached_buffers) do
					local bname = vim.api.nvim_buf_get_name(bufnr)
					local ft    = vim.bo[bufnr].filetype
					if ft and ft ~= "" then
						bufs_by_ft[ft] = bufs_by_ft[ft] or {}
						table.insert(bufs_by_ft[ft], {
							bufnr = bufnr,
							name  = bname ~= "" and vim.fn.fnamemodify(bname, ":~:.") or "[No Name]",
						})
					end
				end
			end

			-- Source: actual EFM config from client settings or state
			local efm_languages = (client.config and client.config.settings and client.config.settings.languages)
				or state.efm_configs
				or {}

			-- Collect linters and formatters
			local linters, formatters = {}, {}
			for ft, cfgs in pairs(efm_languages) do
				for _, cfg in ipairs(cfgs) do
					if cfg.lPrefix or (cfg.lintCommand and cfg.lintCommand ~= "") then
						local name = cfg.server_name or cfg.lPrefix or "Unknown"
						if not linters[name] then
							linters[name] = { filetypes = {}, bufs = {}, cmd = cfg.lintCommand or cfg.lPrefix or "" }
						end
						table.insert(linters[name].filetypes, ft)
						linters[name].bufs[ft] = bufs_by_ft[ft]
					end
					if cfg.fPrefix or (cfg.formatCommand and cfg.formatCommand ~= "") then
						local name = cfg.server_name or cfg.fPrefix or "Unknown"
						if not formatters[name] then
							formatters[name] = { filetypes = {}, bufs = {}, cmd = cfg.formatCommand or cfg.fPrefix or "" }
						end
						table.insert(formatters[name].filetypes, ft)
						formatters[name].bufs[ft] = bufs_by_ft[ft]
					end
				end
			end

			local function render_efm_tools(map, section_label, section_hl)
				if not next(map) then return end
				add_section(ICONS.diamond, section_label, section_hl)
				local names = vim.tbl_keys(map)
				table.sort(names)
				for _, tool_name in ipairs(names) do
					local tool = map[tool_name]
					-- Tool header
					table.insert(lines, L2 .. ICONS.circle .. " " .. tool_name
						.. "  (" .. table.concat(tool.filetypes, ", ") .. ")")
					add_hl(#lines - 1, tool_name, "LvimLspInfoToolName")
					add_icon_hl(#lines - 1, ICONS.circle)
					-- Command
					if tool.cmd and tool.cmd ~= "" then
						local cmd = tool.cmd
						if #cmd > popup_width - 14 then cmd = cmd:sub(1, popup_width - 17) .. "..." end
						table.insert(lines, L3 .. "Command: " .. cmd)
						add_hl(#lines - 1, "Command:", "LvimLspInfoKey")
					end
					-- Per-filetype: buffers + diagnostics
					local seen_bufs = {}
					for _, ft in ipairs(tool.filetypes) do
						local ft_bufs = tool.bufs[ft]
						if ft_bufs and #ft_bufs > 0 then
							table.insert(lines, L3 .. "Filetype: " .. ft)
							add_hl(#lines - 1, "Filetype:", "LvimLspInfoKey")
							for _, buf in ipairs(ft_bufs) do
								if not seen_bufs[buf.bufnr] then
									seen_bufs[buf.bufnr] = true
									local bc  = client_diag_counts(client.id, buf.bufnr)
									local sev = vim.diagnostic.severity
									local bdiag = string.format("%s %d  %s %d  %s %d  %s %d",
										ICONS.cross, bc[sev.ERROR],
										ICONS.warn,  bc[sev.WARN],
										ICONS.info,  bc[sev.INFO],
										ICONS.hint,  bc[sev.HINT])
									table.insert(lines, L3 .. ICONS.circle
										.. " [" .. buf.bufnr .. "] " .. buf.name
										.. "    " .. bdiag)
									add_icon_hl(#lines - 1, ICONS.circle)
									add_hl(#lines - 1, ICONS.cross, "DiagnosticError")
									add_hl(#lines - 1, ICONS.warn,  "DiagnosticWarn")
									add_hl(#lines - 1, ICONS.info,  "DiagnosticInfo")
									add_hl(#lines - 1, ICONS.hint,  "DiagnosticHint")
								end
							end
						end
					end
				end
			end

			render_efm_tools(linters,    "Linters",    "LvimLspInfoLinter")
			render_efm_tools(formatters, "Formatters", "LvimLspInfoFormatter")

			-- Overall EFM diagnostics
			local dc = client_diag_counts(client.id, nil)
			add_section(ICONS.diamond, "Diagnostics (total)", "LvimLspInfoSection")
			table.insert(lines, L2 .. diag_summary(dc, ICONS))
			add_hl(#lines - 1, ICONS.cross, "DiagnosticError")
			add_hl(#lines - 1, ICONS.warn,  "DiagnosticWarn")
			add_hl(#lines - 1, ICONS.info,  "DiagnosticInfo")
			add_hl(#lines - 1, ICONS.hint,  "DiagnosticHint")

			-- Supported filetypes
			local fts = client.config and client.config.filetypes or {}
			if #fts > 0 then
				add_section(ICONS.diamond, "Supported Filetypes", "LvimLspInfoSection")
				table.insert(lines, L2 .. table.concat(fts, ", "))
			end

			-- Server Capabilities
			local sc_full = client.server_capabilities
			if sc_full and type(sc_full) == "table" and next(sc_full) ~= nil then
				add_section(ICONS.diamond, "Server Capabilities", "LvimLspInfoSection")
				local fold_start = #lines
				render_settings(sc_full, L2)
				local fold_end = #lines - 1
				if fold_end > fold_start then
					table.insert(folds, { start_line = fold_start - 1, end_line = fold_end })
				end
			end

			-- Settings
			local settings = client.config and client.config.settings
			if settings and type(settings) == "table" and next(settings) ~= nil then
				add_section(ICONS.diamond, "Settings", "LvimLspInfoSection")
				local fold_start = #lines
				render_settings(settings, L2)
				local fold_end = #lines - 1
				if fold_end > fold_start then
					table.insert(folds, { start_line = fold_start - 1, end_line = fold_end })
				end
			end

		-- ── Non-EFM client ────────────────────────────────────────────────────
		else
			-- Info line: filetypes | encoding | PID
			local fts = client.config and client.config.filetypes or {}
			local enc = client.offset_encoding or "?"
			local pid = client_pid(client)
			local info_parts = {}
			if #fts > 0 then
				table.insert(info_parts, "Filetypes: " .. table.concat(fts, ", "))
			end
			table.insert(info_parts, "Encoding: " .. enc)
			if pid then table.insert(info_parts, "PID: " .. pid) end
			table.insert(lines, L1 .. table.concat(info_parts, "  │  "))
			add_hl(#lines - 1, "Filetypes:",  "LvimLspInfoKey")
			add_hl(#lines - 1, "Encoding:",   "LvimLspInfoKey")
			if pid then add_hl(#lines - 1, "PID:", "LvimLspInfoKey") end

			-- Command
			if client.cmd and #client.cmd > 0 then
				local cmd = sanitize(table.concat(client.cmd, " "))
				if #cmd > popup_width - 12 then cmd = cmd:sub(1, popup_width - 15) .. "..." end
				table.insert(lines, L1 .. "Command: " .. cmd)
				add_hl(#lines - 1, "Command:", "LvimLspInfoKey")
			end

			-- Flags
			local flags = client.config and client.config.flags
			if flags and next(flags) then
				local fparts = {}
				if flags.debounce_text_changes then
					table.insert(fparts, "debounce: " .. flags.debounce_text_changes .. "ms")
				end
				if flags.allow_incremental_sync ~= nil then
					table.insert(fparts, "incremental_sync: " .. tostring(flags.allow_incremental_sync))
				end
				if #fparts > 0 then
					table.insert(lines, L1 .. "Flags: " .. table.concat(fparts, "  │  "))
					add_hl(#lines - 1, "Flags:", "LvimLspInfoKey")
				end
			end

			-- Root Directory
			if client.config and client.config.root_dir then
				add_section(ICONS.diamond, "Root Directory", "LvimLspInfoSection")
				local rd = type(client.config.root_dir) == "function"
					and "<function>"
					or  sanitize(client.config.root_dir)
				table.insert(lines, L2 .. rd)
			end

			-- Workspace Folders
			local wfolders = client.workspace_folders
			if wfolders and #wfolders > 0 then
				add_section(ICONS.diamond, "Workspace Folders", "LvimLspInfoSection")
				for _, wf in ipairs(wfolders) do
					local path = sanitize(vim.uri_to_fname(wf.uri))
					table.insert(lines, L2 .. ICONS.circle .. " " .. path)
					add_icon_hl(#lines - 1, ICONS.circle)
				end
			end

			-- Capabilities tick-list
			add_section(ICONS.diamond, "Capabilities", "LvimLspInfoSection")
			local has_cap = false
			local sc = client.server_capabilities
			if sc then
				for _, cap in ipairs({
					{ "Completion",          sc.completionProvider },
					{ "Hover",               sc.hoverProvider },
					{ "Go to Definition",    sc.definitionProvider },
					{ "Find References",     sc.referencesProvider },
					{ "Document Formatting", sc.documentFormattingProvider },
					{ "Document Symbols",    sc.documentSymbolProvider },
					{ "Workspace Symbols",   sc.workspaceSymbolProvider },
					{ "Rename",              sc.renameProvider },
					{ "Code Action",         sc.codeActionProvider },
					{ "Signature Help",      sc.signatureHelpProvider },
					{ "Document Highlight",  sc.documentHighlightProvider },
					{ "Inlay Hints",         sc.inlayHintProvider },
					{ "Semantic Tokens",     sc.semanticTokensProvider },
				}) do
					if cap[2] then
						has_cap = true
						table.insert(lines, L2 .. ICONS.check .. " " .. cap[1])
						add_icon_hl(#lines - 1, ICONS.check)
					end
				end
			end
			if not has_cap then
				table.insert(lines, L2 .. ICONS.cross .. " No capabilities detected")
				add_icon_hl(#lines - 1, ICONS.cross)
			end

			-- Diagnostics
			local dc = client_diag_counts(client.id, nil)
			add_section(ICONS.diamond, "Diagnostics", "LvimLspInfoSection")
			table.insert(lines, L2 .. diag_summary(dc, ICONS))
			add_hl(#lines - 1, ICONS.cross, "DiagnosticError")
			add_hl(#lines - 1, ICONS.warn,  "DiagnosticWarn")
			add_hl(#lines - 1, ICONS.info,  "DiagnosticInfo")
			add_hl(#lines - 1, ICONS.hint,  "DiagnosticHint")

			-- Attached Buffers + per-buffer diagnostics
			add_section(ICONS.diamond, "Attached Buffers", "LvimLspInfoSection")
			local has_bufs = false
			if client.attached_buffers then
				for bufnr in pairs(client.attached_buffers) do
					has_bufs = true
					local name    = vim.api.nvim_buf_get_name(bufnr)
					local display = sanitize(name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "[No Name]")
					local ft      = vim.bo[bufnr].filetype
					local bc      = client_diag_counts(client.id, bufnr)
					local sev     = vim.diagnostic.severity
					local bdiag   = string.format("%s %d  %s %d  %s %d  %s %d",
						ICONS.cross, bc[sev.ERROR],
						ICONS.warn,  bc[sev.WARN],
						ICONS.info,  bc[sev.INFO],
						ICONS.hint,  bc[sev.HINT])
					local bufline = L2 .. ICONS.circle .. " [" .. bufnr .. "] " .. display
					if ft and ft ~= "" then bufline = bufline .. " (" .. ft .. ")" end
					bufline = bufline .. "    " .. bdiag
					table.insert(lines, bufline)
					add_icon_hl(#lines - 1, ICONS.circle)
					add_hl(#lines - 1, "Buffer", "LvimLspInfoBuffer")
					add_hl(#lines - 1, ICONS.cross, "DiagnosticError")
					add_hl(#lines - 1, ICONS.warn,  "DiagnosticWarn")
					add_hl(#lines - 1, ICONS.info,  "DiagnosticInfo")
					add_hl(#lines - 1, ICONS.hint,  "DiagnosticHint")
				end
			end
			if not has_bufs then
				table.insert(lines, L2 .. ICONS.cross .. " No buffers attached")
				add_icon_hl(#lines - 1, ICONS.cross)
			end

			-- Mason
			local mpkgs = mason_info(client.name)
			if #mpkgs > 0 then
				add_section(ICONS.diamond, "Mason", "LvimLspInfoSection")
				for _, mpkg in ipairs(mpkgs) do
					table.insert(lines, L2 .. ICONS.check .. " " .. mpkg.name .. "  " .. mpkg.version)
					add_icon_hl(#lines - 1, ICONS.check)
					add_hl(#lines - 1, mpkg.name, "LvimLspInfoServerName")
				end
			end

			-- Server Capabilities (full spec reported by the server)
			local sc_full = client.server_capabilities
			if sc_full and type(sc_full) == "table" and next(sc_full) ~= nil then
				add_section(ICONS.diamond, "Server Capabilities", "LvimLspInfoSection")
				local fold_start = #lines
				render_settings(sc_full, L2)
				local fold_end = #lines - 1
				if fold_end > fold_start then
					table.insert(folds, { start_line = fold_start - 1, end_line = fold_end })
				end
			end

			-- Settings (our config passed to the server)
			local settings = client.config and client.config.settings
			if settings and type(settings) == "table" and next(settings) ~= nil then
				add_section(ICONS.diamond, "Settings", "LvimLspInfoSection")
				local fold_start = #lines
				render_settings(settings, L2)
				local fold_end = #lines - 1
				if fold_end > fold_start then
					table.insert(folds, { start_line = fold_start - 1, end_line = fold_end })
				end
			end
		end

		table.insert(lines, "")
		add_sep(popup_width)
	end

	-- ── Open window via lvim-utils ────────────────────────────────────────────

	local info_mod = require("lvim-lsp.ui").get()
	if not info_mod then
		vim.notify("lvim-lsp: lvim-utils is required for LvimLvimLspInfo", vim.log.levels.ERROR)
		return
	end

	-- Strip any embedded newlines that would crash nvim_buf_set_lines.
	for i, line in ipairs(lines) do
		lines[i] = line:gsub("[\n\r]", " ")
	end

	local keys_cfg = state.config.popup_global and state.config.popup_global.keys or {}
	local back_key = keys_cfg.back or "u"

	-- Flag: true when user pressed back_key (u), false when pressing q/Esc
	local go_back = false

	local buf_ref, win_ref
	info_mod.info(lines, {
		title       = state.config.info.popup_title,
		readonly    = true,
		zindex      = 250,
		hide_cursor = false,
		highlights  = highlights,
		folds       = folds,
		fold_icon   = ICONS.fold,
		back_key    = on_back and back_key or nil,
		callback    = on_back and function()
			if go_back then on_back() end
		end or nil,
		on_open     = function(buf, win)
			buf_ref = buf
			win_ref = win
			vim.wo[win].wrap       = false
			vim.wo[win].cursorline = true
			if on_back then
				vim.keymap.set("n", back_key, function()
					go_back = true
					vim.api.nvim_feedkeys(
						vim.api.nvim_replace_termcodes("q", true, false, true), "m", false)
				end, { buffer = buf, silent = true, nowait = true })
			end
		end,
	})

	return {
		bufnr = buf_ref,
		win   = win_ref,
		close = function()
			if win_ref and vim.api.nvim_win_is_valid(win_ref) then
				vim.api.nvim_win_close(win_ref, true)
			end
		end,
	}
end

return M
