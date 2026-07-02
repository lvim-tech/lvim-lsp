-- lvim-lsp.ui.symbols: present workspace AND document symbols in the lvim-utils PICKER.
--
-- `workspace/symbol` (word under the cursor) or `textDocument/documentSymbol` (the current file), mapped
-- to picker items (each with its kind icon), opened with a filter bar built from the symbol KINDS actually
-- present ([A]ll + one button per kind). A file preview + jump, mirroring ui/locations.lua.
--
---@module "lvim-lsp.ui.symbols"

local lsp_state = require("lvim-lsp.state")
local notify = require("lvim-ls.utils.notify")
local picker = require("lvim-utils.picker")
local outline = require("lvim-lsp.ui.outline")

local SymbolKind = vim.lsp.protocol.SymbolKind

local M = {}

--- Jump to a location with `cmd` (edit/split/vsplit) and centre it.
---@param it table
---@param cmd? string
local function jump(it, cmd)
    cmd = cmd or "edit"
    if cmd == "edit" then
        local buf = vim.fn.bufadd(it.path)
        vim.fn.bufload(buf)
        vim.api.nvim_win_set_buf(0, buf)
    else
        vim.cmd(cmd .. " " .. vim.fn.fnameescape(it.path))
    end
    pcall(vim.api.nvim_win_set_cursor, 0, { it.lnum, math.max(0, (it.col or 1) - 1) })
    vim.cmd("normal! zz")
end

--- Map one symbol (SymbolInformation OR a hierarchical DocumentSymbol) → a picker item; recurse into a
--- DocumentSymbol's children. `doc_path` is the current file (DocumentSymbols have no uri of their own).
---@param s table
---@param doc_path string
---@param out table[]
---@param kinds table<integer, boolean>
local function add_symbol(s, doc_path, out, kinds)
    local path, rng
    if s.location then -- SymbolInformation
        path, rng = vim.uri_to_fname(s.location.uri), s.location.range
    else -- DocumentSymbol
        path, rng = doc_path, s.selectionRange or s.range
    end
    local icon, icon_hl = outline.kind_icon(s.kind)
    out[#out + 1] = {
        path = path,
        lnum = (rng and rng.start.line or 0) + 1,
        col = (rng and rng.start.character or 0) + 1,
        text = s.name,
        kind = s.kind,
        icon = icon,
        icon_hl = icon_hl,
    }
    kinds[s.kind] = true
    for _, child in ipairs(s.children or {}) do
        add_symbol(child, doc_path, out, kinds)
    end
end

--- Open the symbol picker for `items` (+ the `kinds` present) with the [A]ll / per-kind filter bar.
---@param title string
---@param items table[]
---@param kinds table<integer, boolean>
---@param layout string
local function present(title, items, kinds, layout)
    -- Kind filter: the static [A]ll button (from config.filters.symbols.kind.all) + one button per kind
    -- present (stable order by kind number). Kind buttons carry no hotkey (too many to letter uniquely) —
    -- reached with l/h on the focused filter bar.
    local kcfg = lsp_state.config.filters.symbols.kind
    local buttons = { vim.tbl_extend("force", {}, kcfg.all) }
    local kn = {}
    for k in pairs(kinds) do
        kn[#kn + 1] = k
    end
    table.sort(kn)
    for _, k in ipairs(kn) do
        buttons[#buttons + 1] = {
            id = "k" .. k,
            label = SymbolKind[k] or tostring(k),
            predicate = function(it)
                return it.kind == k
            end,
        }
    end

    picker.open({
        title = title,
        layout = layout,
        list_wrap = ((lsp_state.config.peek or {}).appearance or {}).list_wrap ~= false,
        items = items,
        -- a flat row: `<kind icon> name  tail:lnum` (the preview winbar carries the full path)
        format = function(it)
            local tail = vim.fn.fnamemodify(it.path, ":t")
            return ("%s %s  %s:%d"):format(it.icon or "", it.text or "", tail, it.lnum)
        end,
        preview_file = true,
        subtitle = function(it)
            return vim.fn.fnamemodify(it.path, ":t")
        end,
        on_confirm = function(it)
            jump(it, "edit")
        end,
        filters = { { id = kcfg.id, active = kcfg.active, buttons = buttons } },
        keys = {
            {
                key = "<C-s>",
                name = "split",
                run = function(it, close)
                    close()
                    jump(it, "split")
                end,
            },
            {
                key = "<C-v>",
                name = "vsplit",
                run = function(it, close)
                    close()
                    jump(it, "vsplit")
                end,
            },
        },
    })
end

--- Open the workspace-symbols picker (`layout` = "area" | "float" | "bottom"). Query = word under the cursor.
---@param layout string
function M.workspace(layout)
    local bufnr = vim.api.nvim_get_current_buf()
    if #vim.lsp.get_clients({ bufnr = bufnr, method = "workspace/symbol" }) == 0 then
        notify("No LSP client supporting workspace symbols found.", vim.log.levels.WARN)
        return
    end
    local query = vim.fn.expand("<cword>") or ""
    vim.lsp.buf_request_all(bufnr, "workspace/symbol", { query = query }, function(results)
        local items, kinds = {}, {}
        for _, r in pairs(results or {}) do
            for _, s in ipairs(r.result or {}) do
                if s.location and s.location.uri then
                    add_symbol(s, "", items, kinds)
                end
            end
        end
        if #items == 0 then
            notify("No workspace symbols for '" .. query .. "'.", vim.log.levels.INFO)
            return
        end
        present("Workspace Symbols", items, kinds, layout)
    end)
end

--- Open the document-symbols picker for the current file (`layout` = "area" | "float" | "bottom").
---@param layout string
function M.document(layout)
    local bufnr = vim.api.nvim_get_current_buf()
    if #vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/documentSymbol" }) == 0 then
        notify("No LSP client supporting document symbols found.", vim.log.levels.WARN)
        return
    end
    local doc_path = vim.api.nvim_buf_get_name(bufnr)
    local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
    vim.lsp.buf_request_all(bufnr, "textDocument/documentSymbol", params, function(results)
        local items, kinds = {}, {}
        for _, r in pairs(results or {}) do
            for _, s in ipairs(r.result or {}) do
                add_symbol(s, doc_path, items, kinds)
            end
        end
        if #items == 0 then
            notify("No document symbols found.", vim.log.levels.INFO)
            return
        end
        present("Document Symbols", items, kinds, layout)
    end)
end

return M
