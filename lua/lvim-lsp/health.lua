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
    if vim.fn.has("nvim-0.12") == 1 then
        h.ok("Neovim >= 0.12")
    else
        h.error("Neovim >= 0.12 is required")
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

    -- The location / diagnostics peek renders through lvim-picker; without it every non-native peek is
    -- unavailable. lvim-picker in turn routes the peek through lvim-utils.dock (a single stable
    -- `lvim-picker:lsp-peek` entry) — report the dock too, since that governs the peek's stacking.
    if pcall(require, "lvim-picker") then
        h.ok("lvim-picker found (renders the location / diagnostics peek)")
        if pcall(require, "lvim-utils.dock") then
            local peek = (require("lvim-lsp.state").config or {}).peek or {}
            if peek.dock_stack ~= false then
                h.ok("lvim-utils.dock found — the peek joins the shared dock stack (config.peek.dock_stack = true)")
            else
                h.info("lvim-utils.dock found, but config.peek.dock_stack = false — the peek opens standalone")
            end
        else
            h.info("lvim-utils.dock not found — the peek opens un-docked (no <Leader>n/p/x/m cycling)")
        end
    else
        h.warn("lvim-picker not found — the non-native location / diagnostics peek is unavailable")
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

    -- ── configured servers (deep) ─────────────────────────────────────────────
    -- Per server: are its required tools installed (via the engine's missing-tools check) and
    -- does it currently have a running client. Surfaces "why isn't X running" at a glance.
    local ok_mgr, manager = pcall(require, "lvim-ls.core.manager")
    if ok_state and ok_mgr then
        local names = vim.tbl_keys((ls_state.config or {}).file_types or {})
        table.sort(names)
        local running = {}
        for _, client in ipairs(vim.lsp.get_clients()) do
            running[client.name] = true
        end
        local missing_any = false
        for _, name in ipairs(names) do
            local missing = manager.missing_tools_for_server(name)
            if #missing > 0 then
                missing_any = true
                h.warn(("%s — missing tool(s): %s"):format(name, table.concat(missing, ", ")))
            end
        end
        if not missing_any and #names > 0 then
            h.ok(("all %d configured server(s) have their tools installed"):format(#names))
        end
        local run_names = vim.tbl_keys(running)
        table.sort(run_names)
        h.info("running clients: " .. (#run_names > 0 and table.concat(run_names, ", ") or "none"))
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

    -- ── lightbulb ─────────────────────────────────────────────────────────────
    if ok_ui then
        local lb = ui_state.config.lightbulb or {}
        if lb.enabled == false then
            h.info("lightbulb disabled (config.lightbulb.enabled = false)")
        else
            h.ok(
                ("lightbulb enabled — placement=%s update_ms=%s only=%s"):format(
                    tostring(lb.placement or "virtual_text"),
                    tostring(lb.update_ms or 150),
                    lb.only and table.concat(lb.only, ",") or "all"
                )
            )
        end
    end
end

return M
