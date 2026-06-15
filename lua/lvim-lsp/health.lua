-- lvim-lsp: :checkhealth lvim-lsp
--
-- Checks the pieces the LSP UI LAYER needs: the lvim-ls engine it drives, lvim-utils for the
-- popup palette, the optional lvim-pkg (install prompt + declined list) and mason-registry
-- (info-window versions), the EFM binary, and whether setup() has run. The engine's own
-- prerequisites are reported separately by :checkhealth lvim-ls.
--
---@module "lvim-lsp.health"

local M = {}

function M.check()
    local h = vim.health
    h.start("lvim-lsp")

    -- ── core ──────────────────────────────────────────────────────────────────
    if vim.fn.has("nvim-0.11") == 1 then
        h.ok("Neovim >= 0.11 (vim.diagnostic.jump, bordered vim.lsp.buf.*)")
    elseif vim.fn.has("nvim-0.10") == 1 then
        h.warn("Neovim 0.10 — works, but diagnostic jump/border options need 0.11")
    else
        h.error("Neovim >= 0.10 is required")
    end

    -- ── required dependencies ─────────────────────────────────────────────────
    local ok_ls = pcall(require, "lvim-ls.state")
    if ok_ls then
        h.ok("lvim-ls found (the LSP engine this UI drives)")
    else
        h.error("lvim-ls not found — lvim-lsp is only the UI layer and cannot run without it")
    end

    local ok_utils = pcall(require, "lvim-utils.utils")
    local ok_colors, colors = pcall(require, "lvim-utils.colors")
    if ok_utils and ok_colors and type(colors.on_change) == "function" then
        h.ok("lvim-utils found (popup palette + merge)")
    else
        h.error("lvim-utils not found — popups and the LvimLsp* highlights need it")
    end

    -- ── optional dependencies ─────────────────────────────────────────────────
    local ok_pkg, pkg = pcall(require, "lvim-pkg")
    if ok_pkg and type(pkg.declined) == "function" then
        h.ok("lvim-pkg found (install prompt + :LvimLsp declined)")
    else
        h.warn("lvim-pkg not found — the install prompt and :LvimLsp declined are unavailable")
    end

    if pcall(require, "mason-registry") then
        h.ok("mason-registry found (tool versions in the :LvimLsp info window)")
    else
        h.info("mason-registry not found — the info window omits Mason package versions")
    end

    -- ── setup state ───────────────────────────────────────────────────────────
    local ok_state, ls_state = pcall(require, "lvim-ls.state")
    if ok_state then
        local cfg = ls_state.config or {}
        if type(cfg.file_types) == "table" and next(cfg.file_types) then
            h.ok(("setup() ran — %d file_types configured"):format(vim.tbl_count(cfg.file_types)))
        else
            h.warn("no file_types configured — call require('lvim-lsp').setup({ file_types = … })")
        end
        local exe = (cfg.efm or {}).executable or "efm-langserver"
        if vim.fn.executable(exe) == 1 then
            h.ok("EFM binary on PATH: " .. exe)
        else
            h.info(exe .. " not on PATH — installed on demand when a filetype needs a formatter/linter")
        end
    end

    -- ── progress config ───────────────────────────────────────────────────────
    -- Behaviour (enabled / done_ttl) lives in the engine; appearance (render_limit) in the UI.
    local ok_ui, ui_state = pcall(require, "lvim-lsp.state")
    if ok_ui and ok_state then
        local engine = (ls_state.config or {}).progress or {}
        local ui = ui_state.config.progress or {}
        h.info(
            ("progress=%s  done_ttl=%sms  render_limit=%s"):format(
                tostring(engine.enabled ~= false),
                tostring(engine.done_ttl or "?"),
                tostring(ui.render_limit or "?")
            )
        )
    end
end

return M
