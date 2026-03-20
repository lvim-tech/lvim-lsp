-- lvim-lsp: user-facing commands, keymaps, and interactive menus.
-- Registers Neovim user-commands that wrap vim.lsp.buf.* calls and provides
-- interactive menus (via lvim-utils UI) for toggling, restarting, and
-- inspecting LSP servers both globally and per-buffer.
--
---@module "lvim-lsp.core.commands"

local state = require("lvim-lsp.state")
local lsp_manager = require("lvim-lsp.core.manager")
local notify = require("lvim-lsp.utils.notify")

-- ── toggle_servers_globally ───────────────────────────────────────────────────

local function toggle_servers_globally()
	local running = {}
	for _, client in ipairs(vim.lsp.get_clients()) do
		running[client.name] = true
	end

	local seen = {}
	if state.file_types then
		for name in pairs(state.file_types) do
			seen[name] = true
		end
	end
	for name in pairs(running) do
		seen[name] = true
	end
	local disabled = state.disabled_servers or {}
	if #state.efm_filetypes > 0 or running["efm"] or disabled["efm"] then
		seen["efm"] = true
	end

	local server_names = vim.tbl_keys(seen)
	table.sort(server_names)

	if #server_names == 0 then
		notify("No LSP servers configured.", vim.log.levels.INFO)
		return
	end

	-- checked = currently running and not disabled
	local initial_selected = {}
	for _, name in ipairs(server_names) do
		if running[name] and not disabled[name] then
			initial_selected[name] = true
		end
	end

	local menus_cfg = (state.config.menus or {}).toggle_servers or {}
	require("lvim-lsp.ui").get().multiselect({
		title = menus_cfg.title,
		subtitle = menus_cfg.subtitle,
		items = server_names,
		initial_selected = initial_selected,
		callback = function(confirmed, selected)
			if not confirmed then
				return
			end
			for _, name in ipairs(server_names) do
				if selected and selected[name] then
					lsp_manager.enable_lsp_server_globally(name)
					lsp_manager.start_language_server(name, true)
				else
					lsp_manager.disable_lsp_server_globally(name)
				end
			end
		end,
	})
end

-- ── toggle_servers_for_buffer ─────────────────────────────────────────────────

local function toggle_servers_for_buffer(bufnr)
	local current_bufnr = bufnr or vim.api.nvim_get_current_buf()
	local ft = vim.bo[current_bufnr].filetype
	if not ft or ft == "" then
		notify("Current buffer has no filetype", vim.log.levels.WARN)
		return
	end

	local all_compatible = lsp_manager.get_compatible_lsp_for_ft(ft)
	local server_names = {}
	for _, name in ipairs(all_compatible) do
		if not lsp_manager.is_server_disabled_globally(name) then
			table.insert(server_names, name)
		end
	end
	table.sort(server_names)

	if #server_names == 0 then
		notify("No compatible LSP servers for filetype: " .. ft, vim.log.levels.WARN)
		return
	end

	-- checked = currently attached to buffer
	local attached = {}
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = current_bufnr })) do
		attached[client.name] = true
	end

	local initial_selected = {}
	for _, name in ipairs(server_names) do
		if attached[name] then
			initial_selected[name] = true
		end
	end

	local menus_cfg = (state.config.menus or {}).toggle_servers_buffer or {}
	require("lvim-lsp.ui").get().multiselect({
		title = menus_cfg.title,
		subtitle = ft,
		items = server_names,
		initial_selected = initial_selected,
		callback = function(confirmed, selected)
			if not confirmed then
				return
			end
			for _, name in ipairs(server_names) do
				if selected and selected[name] then
					lsp_manager.enable_lsp_server_for_buffer(name, current_bufnr)
				else
					lsp_manager.disable_lsp_server_for_buffer(name, current_bufnr)
				end
			end
		end,
	})
end

-- ── lsp_reattach ──────────────────────────────────────────────────────────────

local function lsp_reattach()
	local current_bufnr = vim.api.nvim_get_current_buf()
	local ft = vim.bo[current_bufnr].filetype
	if not ft or ft == "" then
		notify("Current buffer has no filetype", vim.log.levels.WARN)
		return
	end

	local compatible = lsp_manager.get_compatible_lsp_for_ft(ft)
	local server_names = {}
	for _, name in ipairs(compatible) do
		if
			not lsp_manager.is_server_disabled_globally(name)
			and not lsp_manager.is_server_disabled_for_buffer(name, current_bufnr)
		then
			table.insert(server_names, name)
		end
	end
	table.sort(server_names)

	if #server_names == 0 then
		notify("No servers available for filetype: " .. ft, vim.log.levels.INFO)
		return
	end

	-- checked = not yet attached (i.e. candidates for reattach)
	local attached = {}
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = current_bufnr })) do
		attached[client.name] = true
	end

	local initial_selected = {}
	for _, name in ipairs(server_names) do
		if not attached[name] then
			initial_selected[name] = true
		end
	end

	local menus_cfg = (state.config.menus or {}).reattach or {}
	require("lvim-lsp.ui").get().multiselect({
		title = menus_cfg.title,
		subtitle = ft,
		items = server_names,
		initial_selected = initial_selected,
		callback = function(confirmed, selected)
			if not confirmed then
				return
			end
			for _, name in ipairs(server_names) do
				if selected and selected[name] then
					lsp_manager.ensure_lsp_for_buffer(name, current_bufnr)
				end
			end
		end,
	})
end

-- ── lsp_restart ───────────────────────────────────────────────────────────────

local function lsp_restart()
	local running_clients = vim.lsp.get_clients()
	if #running_clients == 0 then
		notify("No LSP servers are running.", vim.log.levels.INFO)
		return
	end

	local seen = {}
	local server_names = {}
	for _, client in ipairs(running_clients) do
		if not seen[client.name] then
			seen[client.name] = true
			table.insert(server_names, client.name)
		end
	end
	table.sort(server_names)

	local initial_selected = {}
	for _, name in ipairs(server_names) do
		initial_selected[name] = true
	end

	local function do_restart(selected)
		if not selected or vim.tbl_isempty(selected) then
			return
		end
		local count = 0
		for server_name in pairs(selected) do
			local attached_bufs = {}
			for _, client in ipairs(running_clients) do
				if client.name == server_name then
					for bufnr in pairs(client.attached_buffers or {}) do
						table.insert(attached_bufs, bufnr)
					end
					pcall(client.stop, client)
				end
			end
			vim.defer_fn(function()
				local ok, new_cid = pcall(lsp_manager.start_language_server, server_name, true)
				if ok and new_cid then
					for _, bufnr in ipairs(attached_bufs) do
						pcall(vim.lsp.buf_attach_client, bufnr, new_cid)
					end
				end
			end, 500)
			count = count + 1
		end
		if count > 0 then
			notify("Restarting " .. count .. " LSP server(s)...", vim.log.levels.INFO)
		end
	end

	local menus_cfg = (state.config.menus or {}).restart or {}
	require("lvim-lsp.ui").get().multiselect({
		title = menus_cfg.title,
		subtitle = menus_cfg.subtitle,
		items = server_names,
		initial_selected = initial_selected,
		callback = function(confirmed, selected)
			if not confirmed then
				return
			end
			do_restart(selected)
		end,
	})
end

-- ── lsp_info ──────────────────────────────────────────────────────────────────
-- Delegates to lvim-lsp.ui.info — all rendering logic lives there.

local function lsp_info()
	return require("lvim-lsp.ui.info").show()
end

-- ── Registration ──────────────────────────────────────────────────────────────

local M = {}

--- Invisible border (padding without a visible frame).
local _border = {
	{ " ", "FloatBorder" },
	{ " ", "FloatBorder" },
	{ " ", "FloatBorder" },
	{ " ", "FloatBorder" },
	{ " ", "FloatBorder" },
	{ " ", "FloatBorder" },
	{ " ", "FloatBorder" },
	{ " ", "FloatBorder" },
}

--- Register all user commands.  Called once from bootstrap.
function M.setup()
	local diag_cfg = state.config.diagnostics

	-- ── helpers ───────────────────────────────────────────────────────────────

	local function require_method(method, fn)
		return function(opts)
			local clients = vim.lsp.get_clients({ bufnr = 0, method = method })
			if #clients == 0 then
				notify("No LSP client supporting " .. method .. " found", vim.log.levels.WARN)
				return
			end
			fn(opts)
		end
	end

	local function require_client(fn)
		return function(opts)
			if #vim.lsp.get_clients({ bufnr = 0 }) == 0 then
				notify("No active LSP client found", vim.log.levels.WARN)
				return
			end
			fn(opts)
		end
	end

	-- ── subcommand dispatch table ─────────────────────────────────────────────

	local subcommands = {
		hover = require_method("textDocument/hover", function()
			vim.lsp.buf.hover({ border = _border })
		end),
		rename = require_method("textDocument/rename", function()
			vim.lsp.buf.rename(nil, { border = _border })
		end),
		format = require_method("textDocument/formatting", function()
			vim.lsp.buf.format({ async = false })
		end),
		code_action = require_method("textDocument/codeAction", function()
			vim.lsp.buf.code_action({ border = _border })
		end),
		definition = require_method("textDocument/definition", function()
			vim.lsp.buf.definition()
		end),
		type_definition = require_method("textDocument/typeDefinition", function()
			vim.lsp.buf.type_definition()
		end),
		declaration = require_method("textDocument/declaration", function()
			vim.lsp.buf.declaration()
		end),
		references = require_method("textDocument/references", function()
			vim.lsp.buf.references(nil, { border = _border })
		end),
		implementation = require_method("textDocument/implementation", function()
			vim.lsp.buf.implementation()
		end),
		signature_help = require_method("textDocument/signatureHelp", function()
			vim.lsp.buf.signature_help({ border = _border })
		end),
		document_symbol = require_method("textDocument/documentSymbol", function()
			vim.lsp.buf.document_symbol()
		end),
		workspace_symbol = require_method("workspace/symbol", function()
			vim.lsp.buf.workspace_symbol()
		end),
		document_highlight = require_method("textDocument/documentHighlight", function()
			vim.lsp.buf.document_highlight()
		end),
		clear_references = require_method("textDocument/documentHighlight", function()
			vim.lsp.buf.clear_references()
		end),
		incoming_calls = require_method("callHierarchy/incomingCalls", function()
			vim.lsp.buf.incoming_calls()
		end),
		outgoing_calls = require_method("callHierarchy/outgoingCalls", function()
			vim.lsp.buf.outgoing_calls()
		end),
		add_workspace_folder = require_method("workspace/didChangeWorkspaceFolders", function()
			vim.lsp.buf.add_workspace_folder()
		end),
		remove_workspace_folder = require_method("workspace/didChangeWorkspaceFolders", function()
			vim.lsp.buf.remove_workspace_folder()
		end),
		list_workspace_folders = function()
			print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
		end,
		range_format = require_method("textDocument/rangeFormatting", function(opts)
			vim.lsp.buf.format({
				range = { ["start"] = { opts.line1, 0 }, ["end"] = { opts.line2, 0 } },
				async = false,
			})
		end),
		diagnostic_current = require_client(function()
			if diag_cfg.show_line then
				diag_cfg.show_line()
			else
				vim.diagnostic.open_float({
					border = _border --[[@as string]],
				})
			end
		end),
		diagnostic_next = require_client(function()
			if diag_cfg.goto_next then
				diag_cfg.goto_next()
			else
				vim.diagnostic.jump({ count = 1 })
			end
		end),
		diagnostic_prev = require_client(function()
			if diag_cfg.goto_prev then
				diag_cfg.goto_prev()
			else
				vim.diagnostic.jump({ count = -1 })
			end
		end),
		toggle_servers = toggle_servers_globally,
		toggle_servers_buffer = function(opts)
			toggle_servers_for_buffer(tonumber(opts.args))
		end,
		restart = lsp_restart,
		info = lsp_info,
		reattach = lsp_reattach,
		project = function()
			require("lvim-lsp.ui.project").open(vim.api.nvim_get_current_buf())
		end,
		declined = function()
			local declined_mod = require("lvim-lsp.core.declined")
			local all = declined_mod.get_all()
			local items = {}
			for tool_name in pairs(all) do
				table.insert(items, tool_name)
			end
			if #items == 0 then
				notify("No declined LSP tools.", vim.log.levels.INFO)
				return
			end
			table.sort(items)
			-- All items initially checked (= currently declined).
			-- Unchecking a tool removes it from the declined list (re-enables it).
			local initial = {}
			for _, tool in ipairs(items) do
				initial[tool] = true
			end
			local menus_cfg = (state.config.menus or {}).declined or {}
			require("lvim-lsp.ui").get().multiselect({
				title = menus_cfg.title,
				subtitle = menus_cfg.subtitle,
				items = items,
				initial_selected = initial,
				callback = function(confirmed, selected)
					if not confirmed then
						return
					end
					local count = 0
					for _, tool in ipairs(items) do
						-- Unchecked = user wants to re-enable this tool.
						if not selected or not selected[tool] then
							declined_mod.undecline(tool)
							count = count + 1
						end
					end
					if count > 0 then
						notify(
							string.format("Re-enabled %d tool(s). Open a file to trigger install.", count),
							vim.log.levels.INFO
						)
					end
				end,
			})
		end,
	}

	if state.config.dap_local_fn then
		subcommands.dap = function()
			state.config.dap_local_fn()
		end
	end

	local subcommand_names = vim.tbl_keys(subcommands)
	table.sort(subcommand_names)

	-- ── single entry-point command ────────────────────────────────────────────

	vim.api.nvim_create_user_command("LvimLsp", function(opts)
		local sub = opts.fargs[1]
		local fn = subcommands[sub]
		if not fn then
			notify("LvimLsp: unknown subcommand '" .. tostring(sub) .. "'", vim.log.levels.ERROR)
			return
		end
		fn(opts)
	end, {
		nargs = "+",
		range = true,
		complete = function(arg_lead, cmd_line, _)
			local parts = vim.split(cmd_line, "%s+")
			if #parts <= 2 then
				return vim.tbl_filter(function(name)
					return name:find(arg_lead, 1, true) == 1
				end, subcommand_names)
			end
			return {}
		end,
		desc = "LvimLsp — unified LSP interface (:LvimLsp <subcommand>)",
	})
end

return M
