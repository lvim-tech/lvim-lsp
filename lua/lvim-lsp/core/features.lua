-- lvim-lsp: optional LSP feature setup.
-- Handles vim.diagnostic configuration, sign definitions, CodeLens lifecycle,
-- and per-buffer on_attach hooks (document_highlight, auto_format, inlay_hints).
--
---@module "lvim-lsp.core.features"

local state = require("lvim-lsp.state")
local M     = {}

-- ── Diagnostics ───────────────────────────────────────────────────────────────

--- Applies state.config.diagnostics to vim.diagnostic and registers sign symbols.
--- Only sets options that are explicitly non-nil in the config.
function M.setup_diagnostics()
    local cfg = state.config.diagnostics

    local diag_opts = {}
    local keys = { "virtual_text", "virtual_lines", "underline", "severity_sort", "update_in_insert" }
    for _, k in ipairs(keys) do
        if cfg[k] ~= nil then
            diag_opts[k] = cfg[k]
        end
    end

    if cfg.signs then
        local text = {}
        local sev  = vim.diagnostic.severity
        if cfg.signs.error then text[sev.ERROR] = cfg.signs.error end
        if cfg.signs.warn  then text[sev.WARN]  = cfg.signs.warn  end
        if cfg.signs.hint  then text[sev.HINT]  = cfg.signs.hint  end
        if cfg.signs.info  then text[sev.INFO]  = cfg.signs.info  end
        if next(text) then
            diag_opts.signs = { text = text }
        end

        -- Legacy sign symbols for plugins that read the signcolumn directly
        if cfg.signs.error then vim.fn.sign_define("DiagnosticSignError", { text = cfg.signs.error, texthl = "DiagnosticError" }) end
        if cfg.signs.warn  then vim.fn.sign_define("DiagnosticSignWarn",  { text = cfg.signs.warn,  texthl = "DiagnosticWarn"  }) end
        if cfg.signs.hint  then vim.fn.sign_define("DiagnosticSignHint",  { text = cfg.signs.hint,  texthl = "DiagnosticHint"  }) end
        if cfg.signs.info  then vim.fn.sign_define("DiagnosticSignInfo",  { text = cfg.signs.info,  texthl = "DiagnosticInfo"  }) end
    end

    if next(diag_opts) then
        vim.diagnostic.config(diag_opts)
    end
end

-- ── CodeLens ──────────────────────────────────────────────────────────────────

--- Saves the original vim.lsp.codelens functions once so they can be restored.
local function save_codelens_originals()
    if not M._orig_display then
        M._orig_display = vim.lsp.codelens.display
        M._orig_refresh = vim.lsp.codelens.refresh
        M._orig_clear   = vim.lsp.codelens.clear
    end
end

--- Run the CodeLens on or nearest to the current cursor line.
function M.run_code_lens()
    if not state.config.code_lens.enabled then
        vim.notify("CodeLens is disabled", vim.log.levels.WARN)
        return
    end
    local line   = vim.api.nvim_win_get_cursor(0)[1] - 1
    local lenses = vim.lsp.codelens.get(0) or {}

    for _, lens in ipairs(lenses) do
        if lens.range.start.line == line then
            vim.lsp.codelens.run()
            return
        end
    end

    local closest, min_dist = nil, math.huge
    for _, lens in ipairs(lenses) do
        local d = math.abs(lens.range.start.line - line)
        if d < min_dist then min_dist = d; closest = lens end
    end
    if closest then
        vim.api.nvim_win_set_cursor(0, { closest.range.start.line + 1, closest.range.start.character })
        vim.lsp.codelens.run()
    elseif #lenses == 0 then
        vim.notify("No CodeLens found in this buffer", vim.log.levels.WARN)
    else
        vim.notify("No CodeLens on current line", vim.log.levels.INFO)
    end
end

--- Initialises CodeLens based on state.config.code_lens.enabled.
function M.setup_code_lens()
    local cfg = state.config.code_lens
    if not cfg then return end

    save_codelens_originals()

    if cfg.enabled then
        vim.lsp.codelens.display = M._orig_display
        vim.lsp.codelens.refresh = M._orig_refresh
        vim.lsp.codelens.clear   = M._orig_clear

        local group = vim.api.nvim_create_augroup("LvimLspCodeLens", { clear = true })
        vim.api.nvim_create_autocmd({ "LspAttach", "TextChanged", "TextChangedI" }, {
            group    = group,
            callback = function()
                vim.defer_fn(function()
                    if state.config.code_lens.enabled then
                        vim.lsp.codelens.refresh()
                    end
                end, 100)
            end,
        })
        M._codelens_group = group
        vim.schedule(function() vim.lsp.codelens.refresh() end)
    else
        vim.lsp.codelens.display = function() end
        vim.lsp.codelens.refresh = function() end
        vim.lsp.codelens.clear   = function() end
        if M._codelens_group then
            pcall(vim.api.nvim_clear_autocmds, { group = M._codelens_group })
            M._codelens_group = nil
        end
    end

    -- Register commands and double-click (idempotent)
    if not M._commands_registered then
        M._commands_registered = true

        vim.api.nvim_create_user_command("LspCodeLensRun", function()
            M.run_code_lens()
        end, {})

        vim.keymap.set("n", "<2-LeftMouse>", function()
            if not state.config.code_lens.enabled then
                vim.api.nvim_input("<2-LeftMouse>")
                return
            end
            local line = vim.api.nvim_win_get_cursor(0)[1] - 1
            for _, lens in ipairs(vim.lsp.codelens.get(0) or {}) do
                if lens.range.start.line == line then
                    vim.lsp.codelens.run()
                    return
                end
            end
            vim.api.nvim_input("<2-LeftMouse>")
        end, { noremap = true, silent = true })
    end
end

-- ── Per-buffer on_attach hooks ────────────────────────────────────────────────

local function eval_flag(val)
    if type(val) == "function" then return val() end
    return val == true
end

--- Called from manager._start_server_for_buffer's on_attach for every client.
--- Applies document_highlight, auto_format, and inlay_hints.
--- Project config (.lvim-lsp.lua) overrides global config.features values.
---@param client any
---@param bufnr  integer
function M.apply_buffer_features(client, bufnr)
    local feat    = state.config.features
    if not feat then return end

    local project = require("lvim-lsp.core.project")
    local root    = type(client.config) == "table" and client.config.root_dir or nil
    local group   = vim.api.nvim_create_augroup("LvimLspFeatures_" .. bufnr, { clear = false })

    -- Document highlight (no project override — always global)
    if feat.document_highlight and client.server_capabilities.documentHighlightProvider then
        vim.api.nvim_create_autocmd("CursorHold", {
            buffer   = bufnr,
            group    = group,
            callback = function()
                for _, c in pairs(vim.lsp.get_clients({ bufnr = bufnr })) do
                    if c.server_capabilities.documentHighlightProvider then
                        vim.lsp.buf.document_highlight()
                        break
                    end
                end
            end,
        })
        vim.api.nvim_create_autocmd("CursorMoved", {
            buffer   = bufnr,
            group    = group,
            callback = function()
                for _, c in pairs(vim.lsp.get_clients({ bufnr = bufnr })) do
                    if c.server_capabilities.documentHighlightProvider then
                        vim.lsp.buf.clear_references()
                        break
                    end
                end
            end,
        })
    end

    -- Auto-format on save (project config overrides global)
    local af_global = feat.auto_format
    if af_global ~= false and af_global ~= nil
        and client.server_capabilities.documentFormattingProvider
    then
        vim.api.nvim_create_autocmd("BufWritePre", {
            buffer   = bufnr,
            group    = group,
            callback = function()
                local effective = root
                    and project.get_feature(root, "auto_format", af_global)
                    or af_global
                if eval_flag(effective) then
                    vim.lsp.buf.format({ bufnr = bufnr })
                end
            end,
        })
    end

    -- Inlay hints (project config overrides global)
    if vim.lsp.inlay_hint and client.server_capabilities.inlayHintProvider then
        local ih_global = feat.inlay_hints
        if ih_global ~= false and ih_global ~= nil then
            vim.schedule(function()
                local effective = root
                    and project.get_feature(root, "inlay_hints", ih_global)
                    or ih_global
                if eval_flag(effective) then
                    vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
                end
            end)
        end
    end
end

return M
