-- lvim-lsp: info — rich LSP information floating window.
-- Shows active clients, capabilities, EFM linters/formatters, attached buffers
-- and server configuration. Large config tables are collapsed into folds.
-- Requires lvim-utils for the floating window.
--
---@module "lvim-lsp.info"

local state = require("lvim-lsp.state")

local M = {}

-- ── Icons / indent constants ───────────────────────────────────────────────────

local ICONS = {
	square = "■",
	diamond = "◆",
	circle = "●",
	bracket = "[+]",
	cross = "✗",
	check = "✓",
}

local L0 = ""
local L1 = "  "
local L2 = "    "
local L3 = "      "
local L4 = "        "

-- ── Private helpers ────────────────────────────────────────────────────────────

local function format_value(val)
	if type(val) == "string" then
		return '"' .. val .. '"'
	end
	if type(val) == "function" then
		return "<function>"
	end
	if val == nil then
		return "nil"
	end
	return tostring(val)
end

local function deep_copy(t)
	if type(t) ~= "table" then
		return t
	end
	local r = {}
	for k, v in pairs(t) do
		r[k] = deep_copy(v)
	end
	return r
end

local function is_array(t)
	if type(t) ~= "table" then
		return false
	end
	local max, n = 0, 0
	for k in pairs(t) do
		if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then
			return false
		end
		if k > max then
			max = k
		end
		n = n + 1
	end
	return n == max and n > 0
end

-- ── Content builders ──────────────────────────────────────────────────────────

-- lines / highlights / folds accumulate content for the whole window.
-- add_* helpers append into them by reference.

local function make_builders()
	local lines = {}
	local highlights = {} -- { line, col_start, col_end, group }  (0-based content indices)

	local function add_hl(line_idx, substr, group)
		local text = lines[line_idx + 1]
		local s, e = string.find(text, vim.pesc(substr), 1, true)
		if s and e then
			table.insert(highlights, { line = line_idx, col_start = s - 1, col_end = e, group = group })
		end
	end

	local function add_icon_hl(line_idx, icon)
		add_hl(line_idx, icon, "LspIcon")
	end

	local function add_tool_hl(line_idx, tool_name, indent)
		local prefix = (indent or L2) .. ICONS.circle .. " "
		table.insert(highlights, {
			line = line_idx,
			col_start = #prefix,
			col_end = #prefix + #tool_name,
			group = "LspInfoToolName",
		})
	end

	local function add_sep(popup_width, group)
		table.insert(lines, string.rep("─", popup_width))
		table.insert(
			highlights,
			{ line = #lines - 1, col_start = 0, col_end = -1, group = group or "LspInfoSeparator" }
		)
	end

	local function display_table(tbl, indent)
		if type(tbl) ~= "table" then
			return
		end
		indent = indent or L4

		table.insert(lines, indent .. "{")

		local keys = vim.tbl_keys(tbl)
		table.sort(keys, function(a, b)
			if type(a) == type(b) then
				return tostring(a) < tostring(b)
			end
			return type(a) == "string"
		end)
		for _, k in ipairs(keys) do
			local v = tbl[k]
			if type(v) ~= "function" then
				local ks = tostring(k)
				if type(v) == "table" then
					if vim.tbl_isempty(v) then
						table.insert(lines, indent .. L1 .. ks .. ": {}")
						add_hl(#lines - 1, ks, "LspInfoConfigKey")
					elseif is_array(v) then
						table.insert(lines, indent .. L1 .. ks .. ": [")
						add_hl(#lines - 1, ks, "LspInfoConfigKey")
						for _, item in ipairs(v) do
							if type(item) == "table" then
								display_table(item, indent .. L2)
							else
								table.insert(lines, indent .. L2 .. format_value(item))
							end
						end
						table.insert(lines, indent .. L1 .. "]")
					else
						table.insert(lines, indent .. L1 .. ks .. ": {")
						add_hl(#lines - 1, ks, "LspInfoConfigKey")
						display_table(v, indent .. L2)
						table.insert(lines, indent .. L1 .. "}")
					end
				else
					table.insert(lines, indent .. L1 .. ks .. ": " .. format_value(v))
					add_hl(#lines - 1, ks, "LspInfoConfigKey")
				end
			end
		end

		table.insert(lines, indent .. "}")
	end

	return lines, highlights, add_hl, add_icon_hl, add_tool_hl, add_sep, display_table
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Open the rich LSP information window.
---@return { bufnr: integer, win: integer, close: fun() }|nil
function M.show()
	local clients = vim.lsp.get_clients()
	if #clients == 0 then
		vim.notify("No active LSP clients found", vim.log.levels.INFO)
		return
	end

	local pg = state.config.popup_global
	local pw = pg.width or 0.8
	local popup_width = (type(pw) == "number" and pw <= 1) and math.floor(vim.o.columns * pw)
		or (type(pw) == "number" and pw or math.floor(vim.o.columns * 0.8))

	local lines, highlights, add_hl, add_icon_hl, add_tool_hl, add_sep, display_table = make_builders()

	-- ── Sort clients: EFM first ───────────────────────────────────────────────

	local efm_client, other_clients = nil, {}
	for _, client in ipairs(clients) do
		if client.name == "efm" then
			efm_client = client
		else
			table.insert(other_clients, client)
		end
	end
	local sorted = {}
	if efm_client then
		table.insert(sorted, efm_client)
	end
	for _, c in ipairs(other_clients) do
		table.insert(sorted, c)
	end

	-- ── Per-client sections ───────────────────────────────────────────────────

	for _, client in ipairs(sorted) do
		table.insert(lines, "")
		table.insert(lines, L0 .. ICONS.square .. " " .. client.name .. " (ID: " .. client.id .. ")")
		add_hl(#lines - 1, client.name, "LspInfoServerName")
		add_icon_hl(#lines - 1, ICONS.square)

		-- ── EFM: linters / formatters ─────────────────────────────────────────
		if client.name == "efm" then
			-- Build filetype → buffers map
			local bufs_by_ft = {}
			if client.attached_buffers then
				for bufnr in pairs(client.attached_buffers) do
					local name = vim.api.nvim_buf_get_name(bufnr)
					local ft = vim.bo[bufnr].filetype
					if ft and ft ~= "" then
						bufs_by_ft[ft] = bufs_by_ft[ft] or {}
						table.insert(bufs_by_ft[ft], {
							bufnr = bufnr,
							name = name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "[No Name]",
						})
					end
				end
			end

			-- Deduplicate linters / formatters by name
			local linters, formatters = {}, {}
			for ft, cfgs in pairs(state.efm_configs or {}) do
				for _, cfg in ipairs(cfgs) do
					if cfg.lPrefix or (cfg.lintCommand and cfg.lintCommand ~= "") then
						local name = cfg.server_name or cfg.lPrefix or "Unknown"
						if not linters[name] then
							linters[name] = { config = cfg, filetypes = {}, bufs = {} }
						end
						table.insert(linters[name].filetypes, ft)
						linters[name].bufs[ft] = bufs_by_ft[ft]
					end
					if cfg.fPrefix or (cfg.formatCommand and cfg.formatCommand ~= "") then
						local name = cfg.server_name or cfg.fPrefix or "Unknown"
						if not formatters[name] then
							formatters[name] = { config = cfg, filetypes = {}, bufs = {} }
						end
						table.insert(formatters[name].filetypes, ft)
						formatters[name].bufs[ft] = bufs_by_ft[ft]
					end
				end
			end

			local function render_tools(map, label, hl_group)
				if not next(map) then
					return
				end
				table.insert(lines, L1 .. ICONS.diamond .. " " .. label .. " " .. ICONS.bracket)
				add_hl(#lines - 1, label, hl_group)
				add_icon_hl(#lines - 1, ICONS.diamond)
				add_icon_hl(#lines - 1, ICONS.bracket)
				local names = vim.tbl_keys(map)
				table.sort(names)
				for _, tool_name in ipairs(names) do
					local info = map[tool_name]
					table.insert(
						lines,
						L2
							.. ICONS.circle
							.. " "
							.. tool_name
							.. " (Filetypes: "
							.. table.concat(info.filetypes, ", ")
							.. ")"
					)
					add_tool_hl(#lines - 1, tool_name, L2)
					add_icon_hl(#lines - 1, ICONS.circle)
					display_table(info.config, L3)
					for _, ft in ipairs(info.filetypes) do
						if info.bufs[ft] and #info.bufs[ft] > 0 then
							table.insert(lines, L3 .. ICONS.diamond .. " Buffers")
							add_hl(#lines - 1, "Buffers", "LspInfoSection")
							add_icon_hl(#lines - 1, ICONS.diamond)
							for _, buf in ipairs(info.bufs[ft]) do
								table.insert(
									lines,
									L4
										.. ICONS.circle
										.. " Buffer "
										.. buf.bufnr
										.. ": "
										.. buf.name
										.. " ("
										.. ft
										.. ")"
								)
								add_icon_hl(#lines - 1, ICONS.circle)
								add_hl(#lines - 1, "Buffer", "LspInfoBuffer")
							end
						end
					end
				end
			end

			render_tools(linters, "Linters:", "LspInfoLinter")
			render_tools(formatters, "Formatters:", "LspInfoFormatter")

			local fts = client.config and client.config.filetypes or {}
			if #fts > 0 then
				table.insert(lines, "")
				table.insert(lines, L1 .. ICONS.diamond .. " Supported Filetypes")
				add_hl(#lines - 1, "Supported Filetypes", "LspInfoSection")
				add_icon_hl(#lines - 1, ICONS.diamond)
				table.insert(lines, L2 .. table.concat(fts, ", "))
			end

		-- ── Non-EFM: filetypes + command ──────────────────────────────────────
		else
			if client.config and client.config.filetypes and #client.config.filetypes > 0 then
				table.insert(lines, L1 .. "Filetypes: " .. table.concat(client.config.filetypes, ", "))
				add_hl(#lines - 1, "Filetypes:", "LspInfoKey")
			end
			if client.cmd and #client.cmd > 0 then
				local cmd = table.concat(client.cmd, " ")
				if #cmd > popup_width - 10 then
					cmd = cmd:sub(1, popup_width - 13) .. "..."
				end
				table.insert(lines, L1 .. "Command: " .. cmd)
				add_hl(#lines - 1, "Command:", "LspInfoKey")
			end
		end

		-- ── Server configuration ──────────────────────────────────────────────
		if client.config then
			table.insert(lines, "")
			table.insert(lines, L1 .. ICONS.diamond .. " Server Configuration")
			add_hl(#lines - 1, "Server Configuration", "LspInfoSection")
			add_icon_hl(#lines - 1, ICONS.diamond)
			local has_config = false

			local function cfg_block(label, tbl, fold_id)
				if not tbl or vim.tbl_isempty(tbl) then
					return
				end
				has_config = true
				table.insert(lines, L2 .. ICONS.circle .. " " .. label .. " " .. ICONS.bracket)
				add_hl(#lines - 1, label, "LspInfoKey")
				add_icon_hl(#lines - 1, ICONS.circle)
				add_icon_hl(#lines - 1, ICONS.bracket)
				display_table(deep_copy(tbl), L3)
			end

			cfg_block("Settings:", client.config.settings, "settings_" .. client.name)
			cfg_block("Initialization Options:", client.config.init_options, "init_options_" .. client.name)

			if client.config.root_dir then
				has_config = true
				table.insert(lines, L2 .. ICONS.circle .. " Root Dir:")
				add_hl(#lines - 1, "Root Dir:", "LspInfoKey")
				add_icon_hl(#lines - 1, ICONS.circle)
				table.insert(
					lines,
					L3
						.. (
							type(client.config.root_dir) == "function" and "<function>"
							or tostring(client.config.root_dir)
						)
				)
			end

			cfg_block("Capabilities:", client.config.capabilities, "capabilities_" .. client.name)

			local other = {}
			for k, v in pairs(client.config) do
				if
					not vim.tbl_contains(
						{ "settings", "init_options", "root_dir", "capabilities", "name", "cmd", "filetypes" },
						k
					) and type(v) ~= "function"
				then
					other[k] = deep_copy(v)
				end
			end
			cfg_block("Other Options:", other, "other_options_" .. client.name)

			if not has_config then
				table.insert(lines, L2 .. ICONS.cross .. " No detailed configuration available")
				add_icon_hl(#lines - 1, ICONS.cross)
			end
		end

		-- ── Capabilities tick-list ────────────────────────────────────────────
		table.insert(lines, "")
		table.insert(lines, L1 .. ICONS.diamond .. " Capabilities")
		add_hl(#lines - 1, "Capabilities", "LspInfoSection")
		add_icon_hl(#lines - 1, ICONS.diamond)
		local has_cap = false
		if client.server_capabilities then
			for _, cap in ipairs({
				{ "Completion", client.server_capabilities.completionProvider },
				{ "Hover", client.server_capabilities.hoverProvider },
				{ "Go to Definition", client.server_capabilities.definitionProvider },
				{ "Find References", client.server_capabilities.referencesProvider },
				{ "Document Formatting", client.server_capabilities.documentFormattingProvider },
				{ "Document Symbols", client.server_capabilities.documentSymbolProvider },
				{ "Workspace Symbols", client.server_capabilities.workspaceSymbolProvider },
				{ "Rename", client.server_capabilities.renameProvider },
				{ "Code Action", client.server_capabilities.codeActionProvider },
				{ "Signature Help", client.server_capabilities.signatureHelpProvider },
				{ "Document Highlight", client.server_capabilities.documentHighlightProvider },
			}) do
				if cap[2] then
					has_cap = true
					table.insert(lines, L2 .. ICONS.check .. " " .. cap[1])
					add_icon_hl(#lines - 1, ICONS.check)
					add_hl(#lines - 1, ICONS.check, "LspInfoKey")
				end
			end
		end
		if not has_cap then
			table.insert(lines, L2 .. ICONS.cross .. " No specific capabilities detected")
			add_icon_hl(#lines - 1, ICONS.cross)
		end

		-- ── Attached buffers ──────────────────────────────────────────────────
		table.insert(lines, "")
		table.insert(lines, L1 .. ICONS.diamond .. " Attached Buffers")
		add_hl(#lines - 1, "Attached Buffers", "LspInfoSection")
		add_icon_hl(#lines - 1, ICONS.diamond)
		local has_bufs = false
		if client.attached_buffers then
			for bufnr in pairs(client.attached_buffers) do
				has_bufs = true
				local name = vim.api.nvim_buf_get_name(bufnr)
				local display = name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "[No Name]"
				local ft = vim.bo[bufnr].filetype
				local line = L2 .. ICONS.circle .. " Buffer " .. bufnr .. ": " .. display
				if ft and ft ~= "" then
					line = line .. " (" .. ft .. ")"
				end
				table.insert(lines, line)
				add_icon_hl(#lines - 1, ICONS.circle)
				add_hl(#lines - 1, "Buffer", "LspInfoBuffer")
			end
		end
		if not has_bufs then
			table.insert(lines, L2 .. ICONS.cross .. " No buffers attached")
			add_icon_hl(#lines - 1, ICONS.cross)
		end

		table.insert(lines, "")
		add_sep(popup_width)
	end

	-- ── Open window via lvim-utils ────────────────────────────────────────────

	local info_mod = require("lvim-lsp.ui").get()
	if not info_mod then
		vim.notify("lvim-lsp: lvim-utils is required for LvimLspInfo", vim.log.levels.ERROR)
		return
	end

	local buf_ref, win_ref
	info_mod.info(lines, {
		title = state.config.info.popup_title,
		readonly = false,
		zindex = 250,
		hide_cursor = false,
		highlights = highlights,
		on_open = function(buf, win)
			buf_ref = buf
			win_ref = win
			vim.wo[win].wrap = false
			vim.wo[win].cursorline = true
		end,
	})

	return {
		bufnr = buf_ref,
		win = win_ref,
		close = function()
			if win_ref and vim.api.nvim_win_is_valid(win_ref) then
				vim.api.nvim_win_close(win_ref, true)
			end
		end,
	}
end

return M
