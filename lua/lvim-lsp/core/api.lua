-- lvim-lsp.core.api: the PUBLIC, keymap-friendly navigation API.
--
-- Each feature is one function taking `{ native?, layout? }`. The BACKEND (our public picker/peek vs the
-- native Neovim handler) and the LAYOUT are resolved per-call from opts, falling back to the two global
-- knobs `config.peek.native` (default false = our system) and `config.peek.layout` (default "area").
--
-- Re-exported from `require("lvim-lsp")` and driven by `:LvimLsp <feature> [native|area|float|bottom]`.
--
---@module "lvim-lsp.core.api"

local M = {}

---@return table
local function settings()
    return require("lvim-lsp.state").config.peek or {}
end

--- Resolve { native, layout } from a per-call opts table + the global config defaults.
---@param opts? { native?: boolean, layout?: string }
---@return boolean native, string layout
local function resolve(opts)
    opts = opts or {}
    local s = settings()
    local native = opts.native
    if native == nil then
        native = s.native == true
    end
    local layout = opts.layout or s.layout or "area"
    if layout == "split" then
        layout = "bottom" -- alias
    end
    return native, layout
end

-- ── location-style requests (definition / references / …) ─────────────────────────────────────────────
-- native handler ⟷ our picker (ui.locations).
local LOC_NATIVE = {
    definition = vim.lsp.buf.definition,
    type_definition = vim.lsp.buf.type_definition,
    declaration = vim.lsp.buf.declaration,
    references = function()
        vim.lsp.buf.references()
    end,
    implementation = vim.lsp.buf.implementation,
}

---@param method string
---@param opts? table
local function location(method, opts)
    local native, layout = resolve(opts)
    if native then
        LOC_NATIVE[method]()
    else
        require("lvim-lsp.ui.locations").open(method, layout)
    end
end

---@param opts? { native?: boolean, layout?: string }
function M.definition(opts)
    location("definition", opts)
end
---@param opts? { native?: boolean, layout?: string }
function M.type_definition(opts)
    location("type_definition", opts)
end
---@param opts? { native?: boolean, layout?: string }
function M.declaration(opts)
    location("declaration", opts)
end
---@param opts? { native?: boolean, layout?: string }
function M.references(opts)
    location("references", opts)
end
---@param opts? { native?: boolean, layout?: string }
function M.implementation(opts)
    location("implementation", opts)
end

-- ── diagnostics ───────────────────────────────────────────────────────────────────────────────────────
---@param opts? { native?: boolean, layout?: string }
function M.diagnostics(opts)
    local native, layout = resolve(opts)
    if native then
        vim.diagnostic.setqflist()
    else
        require("lvim-lsp.ui.diagnostics_list").open(layout)
    end
end

-- ── call hierarchy ──────────────────────────────────────────────────────────────────────────────────────
---@param opts? { native?: boolean, layout?: string }
function M.incoming_calls(opts)
    local native, layout = resolve(opts)
    if native then
        vim.lsp.buf.incoming_calls()
    else
        require("lvim-lsp.ui.calls").open("incoming", layout)
    end
end
---@param opts? { native?: boolean, layout?: string }
function M.outgoing_calls(opts)
    local native, layout = resolve(opts)
    if native then
        vim.lsp.buf.outgoing_calls()
    else
        require("lvim-lsp.ui.calls").open("outgoing", layout)
    end
end

-- ── symbols ─────────────────────────────────────────────────────────────────────────────────────────────
---@param opts? { native?: boolean, layout?: string }
function M.workspace_symbol(opts)
    local native, layout = resolve(opts)
    if native then
        vim.lsp.buf.workspace_symbol()
    else
        require("lvim-lsp.ui.symbols").workspace(layout)
    end
end
---@param opts? { native?: boolean, layout?: string }
function M.document_symbol(opts)
    local native, layout = resolve(opts)
    if native then
        vim.lsp.buf.document_symbol()
    else
        require("lvim-lsp.ui.symbols").document(layout)
    end
end

-- ── hover (float, no layout) + outline (always our panel) ────────────────────────────────────────────────
---@param opts? { native?: boolean }
function M.hover(opts)
    opts = opts or {}
    local native = opts.native
    if native == nil then
        native = not (require("lvim-lsp.state").config.hover or {}).enabled
    end
    if native then
        vim.lsp.buf.hover()
    else
        require("lvim-lsp.ui.hover").open()
    end
end

--- Toggle the persistent document-symbol outline side panel (always our UI; no native counterpart).
function M.outline()
    require("lvim-lsp.ui.outline").toggle()
end

--- Parse a command ARG ("native" | "area" | "float" | "bottom" | "split") into an opts table.
---@param arg? string
---@return table
function M.parse_arg(arg)
    if not arg or arg == "" then
        return {}
    end
    if arg == "native" then
        return { native = true }
    end
    return { layout = arg }
end

return M
