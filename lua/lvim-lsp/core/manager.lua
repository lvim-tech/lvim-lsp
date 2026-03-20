-- lvim-lsp: low-level LSP lifecycle manager.
-- Responsible for starting, attaching, detaching, enabling, and disabling LSP
-- clients on a per-buffer and per-project-root basis.  Also manages the EFM
-- language server aggregation and handles cleanup of stale servers after a
-- working-directory change.
--
---@module "lvim-lsp.manager"
---@diagnostic disable: undefined-doc-name, undefined-field

local uv = vim.uv
local state = require("lvim-lsp.state")
local notify = require("lvim-lsp.utils.notify")
local debug = require("lvim-lsp.utils.debug")

local M = {}

-- ── Private helpers ───────────────────────────────────────────────────────────

--- Returns a function that, given a starting path, walks up the directory tree
--- looking for any of the provided `markers` (file or directory names).
--- Returns the first ancestor directory that contains a marker, or nil.
---@param ... string  Marker file/directory names (e.g. ".git", "package.json")
---@return fun(startpath: string): string|nil
local function root_pattern(...)
	local markers = { ... }
	return function(startpath)
		if not startpath or #startpath == 0 then
			return nil
		end
		local path = uv.fs_realpath(startpath) or startpath
		local stat = uv.fs_stat(path)
		if stat and stat.type == "file" then
			path = vim.fn.fnamemodify(path, ":h")
		end
		while path and #path > 0 do
			for _, marker in ipairs(markers) do
				if uv.fs_stat(path .. "/" .. marker) then
					return path
				end
			end
			local parent = vim.fn.fnamemodify(path, ":h")
			if parent == path then
				break
			end
			path = parent
		end
		return nil
	end
end

--- Returns true when `bufnr` is a valid buffer backed by a file on disk.
---@param bufnr integer
---@return boolean
local function is_real_file_buffer(bufnr)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	local name = vim.api.nvim_buf_get_name(bufnr)
	return name ~= nil and name ~= ""
end

--- Returns true when `client_id` is currently attached to `bufnr`.
---@param client_id integer
---@param bufnr     integer|nil
---@return boolean
local function is_client_attached_to_buffer(client_id, bufnr)
	if not client_id then
		return false
	end
	if not bufnr or bufnr == 0 then
		bufnr = vim.api.nvim_get_current_buf()
	end
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	local ok, clients = pcall(vim.lsp.get_clients, { bufnr = bufnr })
	if not ok or type(clients) ~= "table" then
		return false
	end
	for _, c in ipairs(clients) do
		if c and c.id == client_id then
			return true
		end
	end
	return false
end

-- ── Internal EFM config builder ───────────────────────────────────────────────

--- Builds the EFM server config from all registered tool configurations.
--- When `root_dir` is given, per-project overrides (enabled/command) are applied.
--- This is the canonical EFM config source — no external efm.lua needed.
---@param root_dir string|nil
---@return table|nil
local function build_efm_lsp_config(root_dir)
	local efm_configs = state.efm_configs
	if not efm_configs or vim.tbl_isempty(efm_configs) then
		return nil
	end

	local project_mod = root_dir and require("lvim-lsp.core.project") or nil
	local filetypes = {}
	local languages = {}
	local root_markers = { ".git" }

	for ft, lang_config in pairs(efm_configs) do
		local active_tools = {}
		for _, tool in ipairs(lang_config) do
			-- Always collect root markers regardless of enabled state.
			if tool.rootMarkers and type(tool.rootMarkers) == "table" then
				for _, marker in ipairs(tool.rootMarkers) do
					if not vim.tbl_contains(root_markers, marker) then
						table.insert(root_markers, marker)
					end
				end
			end
			-- Apply project overrides when a root_dir is known.
			local override = (project_mod and root_dir and tool.server_name)
					and project_mod.load_efm_tool(
						root_dir --[[@as string]],
						tool.server_name --[[@as string]]
					)
				or {}
			if override.enabled ~= false then
				local t = vim.deepcopy(tool)
				if override.command then
					if t.formatCommand then
						t.formatCommand = override.command
					end
					if t.lintCommand then
						t.lintCommand = override.command
					end
				end
				table.insert(active_tools, t)
			end
		end
		if #active_tools > 0 then
			table.insert(filetypes, ft)
			languages[ft] = active_tools
		end
	end

	if #filetypes == 0 then
		return nil
	end

	return {
		name = "efm",
		cmd = { "efm-langserver" },
		filetypes = filetypes,
		single_file_support = true,
		init_options = {
			documentFormatting = true,
			documentRangeFormatting = true,
		},
		settings = {
			rootMarkers = root_markers,
			languages = languages,
		},
		on_attach = function(client, _)
			client.server_capabilities.documentFormattingProvider = true
			client.server_capabilities.documentRangeFormattingProvider = true
		end,
	}
end

-- ── Public API ─────────────────────────────────────────────────────────────────

--- Returns true when `server_name` has been disabled globally.
---@param server_name string
---@return boolean
M.is_server_disabled_globally = function(server_name)
	return state.disabled_servers[server_name] == true
end

--- Returns true when `server_name` has been disabled for `bufnr`.
---@param server_name string
---@param bufnr       integer
---@return boolean
M.is_server_disabled_for_buffer = function(server_name, bufnr)
	return state.disabled_for_buffer[bufnr] ~= nil and state.disabled_for_buffer[bufnr][server_name] == true
end

--- Returns true when `server_name` supports filetype `ft`.
---@param server_name string
---@param ft          string
---@return boolean
M.is_lsp_compatible_with_ft = function(server_name, ft)
	if not ft or ft == "" then
		return false
	end
	if server_name == "efm" then
		if state.efm_configs[ft] then
			return true
		end
		return vim.tbl_contains(state.efm_filetypes, ft)
	end
	local entry = state.file_types[server_name]
	if not entry then
		return false
	end
	return vim.tbl_contains(entry.filetypes or {}, ft)
end

--- Returns all server names (including EFM when applicable) that declare
--- support for filetype `ft`.
---@param ft string
---@return string[]
M.get_compatible_lsp_for_ft = function(ft)
	if not ft or ft == "" then
		return {}
	end
	local result = {}
	for server_name, entry in pairs(state.file_types) do
		if vim.tbl_contains(entry.filetypes or {}, ft) then
			table.insert(result, server_name)
		end
	end
	if vim.tbl_contains(state.efm_filetypes, ft) or state.efm_configs[ft] then
		table.insert(result, "efm")
	end
	return result
end

--- Attaches (or starts) `server_name` for buffer `bufnr`.
--- Resolution order:
---   1. If a client for the same root_dir already exists, reuse it.
---   2. Otherwise load the server config via state.config.server_config_dirs,
---      resolve the project root, and start a new client.
---@param server_name string
---@param bufnr       integer
---@return integer|nil  Client id on success
M.ensure_lsp_for_buffer = function(server_name, bufnr)
	if not is_real_file_buffer(bufnr) then
		return nil
	end
	if M.is_server_disabled_globally(server_name) or M.is_server_disabled_for_buffer(server_name, bufnr) then
		return nil
	end
	local ft = vim.bo[bufnr].filetype
	if not M.is_lsp_compatible_with_ft(server_name, ft) then
		return nil
	end

	local mason_bin_dir = vim.fn.stdpath("data") .. "/mason/bin/"

	local function is_missing(dep)
		-- Permanently skip deps that don't exist in the Mason registry.
		if state.not_in_registry[dep] then
			return false
		end
		-- Binary in PATH or Mason bin → not missing, regardless of Mason metadata.
		local bin = state.bin_aliases[dep] or dep
		if vim.fn.executable(bin) == 1 or vim.fn.executable(mason_bin_dir .. bin) == 1 then
			return false
		end
		return true
	end

	-- ── Early deps check from file_types (no module load needed) ──────────────
	-- Deps are derived from lsp + formatters + linters + debuggers fields.
	-- EFM is a synthetic server with no file_types entry; handled separately below.
	if server_name ~= "efm" then
		local ft_entry = state.file_types[server_name]
		if ft_entry then
			local missing = {}
			local function check_list(list)
				for _, tool in ipairs(list or {}) do
					local dep = type(tool) == "table" and tool[1] or tool
					if is_missing(dep) then
						table.insert(missing, dep)
					end
				end
			end
			check_list(ft_entry.lsp)
			check_list(ft_entry.formatters)
			check_list(ft_entry.linters)
			check_list(ft_entry.debuggers)
			-- EFM is needed when the server registers formatters or linters.
			if #(ft_entry.formatters or {}) > 0 or #(ft_entry.linters or {}) > 0 then
				if is_missing("efm-langserver") then
					table.insert(missing, "efm-langserver")
				end
			end
			if #missing > 0 then
				if not state.installation_in_progress then
					local declined = require("lvim-lsp.core.declined")
					local all_declined = true
					for _, dep in ipairs(missing) do
						if not declined.is_declined(dep) then
							all_declined = false
							break
						end
					end
					if not all_declined then
						require("lvim-lsp.ui.prompt").add_pending(ft, server_name, { dependencies = missing })
					else
						-- LSP binary missing/declined, but EFM/DAP tools may be installed.
						-- Load the server module to register EFM config so EFM can start.
						for _, dir in ipairs(state.config.server_config_dirs) do
							local ok, mod = pcall(require, dir .. "." .. server_name)
							if ok and type(mod) == "table" then
								if mod.efm then
									M.setup_efm(mod.efm.filetypes, mod.efm.tools)
								end
								if mod.dap then
									require("lvim-lsp.core.dap").setup(mod.dap)
								end
								break
							end
						end
					end
				end
				return nil
			end
		end
	end

	-- ── Load server config ─────────────────────────────────────────────────────
	-- EFM is built internally; all others from config dirs.
	local mod
	if server_name == "efm" then
		local efm_cfg = build_efm_lsp_config(vim.uv.cwd() or vim.fn.getcwd())
		if not efm_cfg then
			return nil
		end
		mod = {
			lsp = {
				root_patterns = efm_cfg.settings.rootMarkers,
				config = efm_cfg,
			},
		}
		-- Ensure efm-langserver binary is available before trying to start it.
		if is_missing("efm-langserver") then
			if not state.installation_in_progress then
				if not require("lvim-lsp.core.declined").is_declined("efm-langserver") then
					require("lvim-lsp.ui.prompt").add_pending(ft, "efm", { dependencies = { "efm-langserver" } })
				end
			end
			return nil
		end
	else
		local ok
		for _, dir in ipairs(state.config.server_config_dirs) do
			ok, mod = pcall(require, dir .. "." .. server_name)
			if ok and type(mod) == "table" then
				break
			end
			mod = nil
		end
		if not mod then
			return nil
		end
	end

	if mod.efm then
		M.setup_efm(mod.efm.filetypes, mod.efm.tools)
	end
	if mod.dap then
		require("lvim-lsp.core.dap").setup(mod.dap)
	end
	if not mod.lsp or not mod.lsp.config then
		return nil
	end
	return M._start_server_for_buffer(server_name, bufnr, mod)
end

--- Internal: attach or start `server_name` for `bufnr` using an already-loaded `mod`.
--- Called both from the synchronous path in ensure_lsp_for_buffer and from
--- the async dependency-install callback.
---@param server_name string
---@param bufnr       integer
---@param mod         table  Already-loaded server config module
---@return integer|nil
M._start_server_for_buffer = function(server_name, bufnr, mod)
	if not is_real_file_buffer(bufnr) then
		return nil
	end

	local fname = vim.api.nvim_buf_get_name(bufnr)
	local lsp = mod.lsp or {}
	local patterns = lsp.root_patterns or { ".git" }
	local finder = root_pattern(unpack(patterns))
	local root_dir = finder(fname) or vim.uv.cwd() or vim.fn.getcwd() --[[@as string]]
	debug(string.format("[%s] root_dir=%s buf=%d", server_name, root_dir, bufnr), vim.log.levels.DEBUG)

	if require("lvim-lsp.core.project").is_server_disabled(root_dir, server_name) then
		debug(string.format("[%s] disabled by project config at %s", server_name, root_dir), vim.log.levels.DEBUG)
		return nil
	end

	state.clients_by_root[server_name] = state.clients_by_root[server_name] or {}
	local client_id = state.clients_by_root[server_name][root_dir]

	if client_id then
		local client = vim.lsp.get_client_by_id(client_id)
		if client then
			if not is_client_attached_to_buffer(client_id, bufnr) then
				debug(
					string.format("[%s] reusing client_id=%d, attaching to buf=%d", server_name, client_id, bufnr),
					vim.log.levels.DEBUG
				)
				vim.lsp.buf_attach_client(bufnr, client_id)
				local lsp_cfg = mod.lsp and mod.lsp.config
				if state.config.on_attach then
					pcall(state.config.on_attach, client, bufnr)
				end
				if type(lsp_cfg) == "table" and type(lsp_cfg.on_attach) == "function" then
					pcall(lsp_cfg.on_attach, client, bufnr)
				end
				pcall(require("lvim-lsp.core.features").apply_buffer_features, client, bufnr)
			end
			return client_id
		end
	end

	local lsp_config = lsp.config
	local config = (type(lsp_config) == "function") and lsp_config() or vim.deepcopy(lsp_config)
	if not config then
		return nil
	end
	config.root_dir = root_dir

	-- Merge project-saved server settings (highest priority)
	local proj_data = require("lvim-lsp.core.project").load_server(root_dir, server_name)
	if proj_data and proj_data.settings and not vim.tbl_isempty(proj_data.settings) then
		config.settings = vim.tbl_deep_extend("force", config.settings or {}, proj_data.settings)
	end

	-- Guard: resolve the binary before spawning.
	-- If the cmd is not in PATH, try Mason's bin directory directly.
	local exe = type(config.cmd) == "table" and config.cmd[1]
	if exe and vim.fn.executable(exe) ~= 1 then
		local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/" .. exe
		if vim.fn.executable(mason_bin) == 1 then
			config.cmd = vim.list_extend({ mason_bin }, { unpack(config.cmd, 2) })
		else
			local msg = string.format("%s: '%s' not found in PATH or Mason bin", server_name, exe)
			notify(msg, vim.log.levels.WARN)
			debug(msg, vim.log.levels.WARN)
			return nil
		end
	end

	local new_client_id = vim.lsp.start({
		name = config.name or server_name,
		cmd = config.cmd,
		root_dir = config.root_dir,
		settings = config.settings,
		init_options = config.init_options,
		before_init = config.before_init,
		capabilities = config.capabilities,
		on_attach = function(client, attached_bufnr)
			if attached_bufnr == bufnr then
				if state.config.on_attach then
					pcall(state.config.on_attach, client, attached_bufnr)
				end
				if config.on_attach then
					pcall(config.on_attach, client, attached_bufnr)
				end
				pcall(require("lvim-lsp.core.features").apply_buffer_features, client, attached_bufnr)
			end
		end,
	}, { bufnr = bufnr })

	if new_client_id then
		state.clients_by_root[server_name][root_dir] = new_client_id
		debug(
			string.format("[%s] started client_id=%d root=%s", server_name, new_client_id, root_dir),
			vim.log.levels.INFO
		)
		return new_client_id
	end
	debug(string.format("[%s] vim.lsp.start returned nil (root=%s)", server_name, root_dir), vim.log.levels.WARN)
	return nil
end

--- Detaches `client_id` from `bufnr` after clearing document highlights.
---@param bufnr     integer
---@param client_id integer
---@return boolean
M.safe_detach_client = function(bufnr, client_id)
	if not bufnr or bufnr <= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	local client = vim.lsp.get_client_by_id(client_id)
	if not client then
		return false
	end
	if is_client_attached_to_buffer(client_id, bufnr) then
		pcall(vim.lsp.buf.clear_references)
		pcall(vim.lsp.buf_detach_client, bufnr, client_id)
		return true
	end
	return false
end

--- Adds `server_name` to the global disabled list and stops all running instances.
---@param server_name string
---@return boolean
M.disable_lsp_server_globally = function(server_name)
	state.disabled_servers[server_name] = true
	for _, client in ipairs(vim.lsp.get_clients()) do
		if client.name == server_name then
			for bufnr in pairs(client.attached_buffers or {}) do
				if vim.api.nvim_buf_is_valid(bufnr) then
					M.safe_detach_client(bufnr, client.id)
				end
			end
			pcall(client.stop, client)
		end
	end
	return true
end

--- Disables `server_name` for a single buffer and detaches it immediately.
---@param server_name string
---@param bufnr       integer
---@return boolean
M.disable_lsp_server_for_buffer = function(server_name, bufnr)
	if not state.disabled_for_buffer[bufnr] then
		state.disabled_for_buffer[bufnr] = {}
	end
	state.disabled_for_buffer[bufnr][server_name] = true
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
		if client.name == server_name then
			M.safe_detach_client(bufnr, client.id)
			break
		end
	end
	return true
end

--- Re-enables `server_name` globally (removes from the disabled list).
--- Does NOT automatically re-attach; callers trigger that separately.
---@param server_name string
---@return boolean
M.enable_lsp_server_globally = function(server_name)
	state.disabled_servers[server_name] = nil
	return true
end

--- Re-enables `server_name` for `bufnr` and immediately re-attaches it when possible.
---@param server_name string
---@param bufnr       integer
---@return boolean
M.enable_lsp_server_for_buffer = function(server_name, bufnr)
	if state.disabled_for_buffer[bufnr] then
		state.disabled_for_buffer[bufnr][server_name] = nil
	end
	if M.is_server_disabled_globally(server_name) then
		return false
	end
	local ft = vim.bo[bufnr].filetype
	if ft and ft ~= "" and M.is_lsp_compatible_with_ft(server_name, ft) and is_real_file_buffer(bufnr) then
		local already_attached = false
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
			if client.name == server_name then
				already_attached = true
				break
			end
		end
		if not already_attached then
			local client_id
			for _, client in ipairs(vim.lsp.get_clients()) do
				if client.name == server_name then
					client_id = client.id
					break
				end
			end
			if client_id then
				pcall(vim.lsp.buf_attach_client, bufnr, client_id)
			else
				M.ensure_lsp_for_buffer(server_name, bufnr)
			end
		end
	end
	return true
end

--- Starts `server_name` by finding a compatible open buffer.
--- When `force` is true, also attaches to every other compatible buffer.
---@param server_name string
---@param force       boolean
---@return integer|nil
M.start_language_server = function(server_name, force)
	if state.installation_in_progress then
		return nil
	end
	if not force and M.is_server_disabled_globally(server_name) then
		return nil
	end

	local function find_compatible_buf()
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if is_real_file_buffer(buf) then
				local buf_ft = vim.bo[buf].filetype
				if buf_ft ~= "" and M.is_lsp_compatible_with_ft(server_name, buf_ft) then
					return buf, buf_ft
				end
			end
		end
		return nil, nil
	end

	local _cur = vim.api.nvim_get_current_buf()
	---@type integer?
	local bufnr = _cur
	---@type string?
	local ft = vim.bo[_cur].filetype
	if not bufnr or not is_real_file_buffer(bufnr) or not M.is_lsp_compatible_with_ft(server_name, ft or "") then
		bufnr, ft = find_compatible_buf()
		if not bufnr or not is_real_file_buffer(bufnr) or not M.is_lsp_compatible_with_ft(server_name, ft or "") then
			if not force then
				return nil
			end
			bufnr = nil
		end
	end
	if not bufnr or not is_real_file_buffer(bufnr) then
		return nil
	end

	local client_id = M.ensure_lsp_for_buffer(server_name, bufnr)

	if force and client_id then
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if buf ~= bufnr and is_real_file_buffer(buf) then
				local buf_ft = vim.bo[buf].filetype
				if buf_ft ~= "" and M.is_lsp_compatible_with_ft(server_name, buf_ft) then
					if not M.is_server_disabled_for_buffer(server_name, buf) then
						vim.lsp.buf_attach_client(buf, client_id)
					end
				end
			end
		end
	end
	return client_id
end

--- Convenience wrapper: starts `server_name` for the current buffer.
---@param server_name string
---@return integer|nil
M.lsp_enable = function(server_name)
	return M.ensure_lsp_for_buffer(server_name, vim.api.nvim_get_current_buf())
end

--- Stops all LSP clients whose root_dir is outside the current working directory.
--- Called on DirChanged to clean up stale servers from the previous project.
---@return integer  Number of servers scheduled to stop
M.stop_servers_for_old_project = function()
	local current_dir = vim.uv.cwd() or vim.fn.getcwd()
	local stopped_count = 0
	for _, client in ipairs(vim.lsp.get_clients()) do
		if client.config and client.config.root_dir then
			local client_root
			if type(client.config.root_dir) == "function" then
				goto continue
			else
				client_root = tostring(client.config.root_dir)
			end
			if client_root ~= current_dir and not vim.startswith(client_root, current_dir) then
				local cid = client.id
				vim.schedule(function()
					local c = vim.lsp.get_client_by_id(cid)
					if c then
						pcall(c.stop, c)
					end
				end)
				stopped_count = stopped_count + 1
			end
		end
		::continue::
	end
	if stopped_count > 0 then
		local msg = string.format("Stopped %d LSP server(s) from other projects.", stopped_count)
		notify(msg, vim.log.levels.INFO)
		debug(msg, vim.log.levels.INFO)
	end
	return stopped_count
end

-- ── EFM management ────────────────────────────────────────────────────────────

---@type uv.uv_timer_t|nil
local efm_restart_timer = nil
local efm_restart_delay = 100
---@type boolean
local efm_setup_in_progress = false

--- Merges `tools_config` into `state.efm_configs` for each filetype in
--- `filetypes`, deduplicating by `server_name`, then restarts EFM.
---@param filetypes    string[]
---@param tools_config table[]
M.setup_efm = function(filetypes, tools_config)
	if efm_setup_in_progress then
		vim.defer_fn(function()
			M.setup_efm(filetypes, tools_config)
		end, 100)
		return
	end
	efm_setup_in_progress = true

	local changed = false
	for _, ft in ipairs(filetypes) do
		state.efm_configs[ft] = state.efm_configs[ft] or {}
		local existing = {}
		for _, tool in ipairs(state.efm_configs[ft]) do
			if tool.server_name then
				existing[tool.server_name] = true
			end
		end
		for _, tool in ipairs(tools_config) do
			if tool.server_name and not existing[tool.server_name] then
				table.insert(state.efm_configs[ft], tool)
				existing[tool.server_name] = true
				changed = true
			end
		end
	end

	if not changed then
		efm_setup_in_progress = false
		return
	end

	vim.schedule(function()
		if efm_restart_timer then
			efm_restart_timer:stop()
			efm_restart_timer:close()
			efm_restart_timer = nil
		end
		efm_restart_timer = vim.uv.new_timer()
		if not efm_restart_timer then
			return
		end
		efm_restart_timer:start(
			efm_restart_delay,
			0,
			vim.schedule_wrap(function()
				if efm_restart_timer then
					efm_restart_timer:stop()
					efm_restart_timer:close()
					efm_restart_timer = nil
				end
				local efm_running = false
				for _, client in ipairs(vim.lsp.get_clients()) do
					if client.name == "efm" then
						efm_running = true
						pcall(client.stop, client)
						break
					end
				end
				vim.defer_fn(function()
					M.start_language_server("efm", true)
					efm_setup_in_progress = false
				end, efm_running and 200 or 0)
			end)
		)
	end)
end

--- Tracks Mason installation status.
--- Transitioning true → false triggers auto-start of newly-available servers
--- and re-attaches them to all open file buffers.
---@param status boolean
M.set_installation_status = function(status)
	local previous = state.installation_in_progress
	state.installation_in_progress = status

	if status == false and previous == true then
		-- Re-run ensure_lsp_for_buffer for every open buffer.
		-- The dep check inside will correctly start servers whose tools are now
		-- installed, without guessing binary names from server identifiers.
		vim.defer_fn(function()
			for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
				if is_real_file_buffer(bufnr) then
					local ft = vim.bo[bufnr].filetype
					if ft and ft ~= "" then
						local servers = M.get_compatible_lsp_for_ft(ft)
						for _, server_name in ipairs(servers) do
							if not M.is_server_disabled_globally(server_name) then
								M.ensure_lsp_for_buffer(server_name, bufnr)
							end
						end
					end
				end
			end
		end, 1000)
	end
end

return M
