-- lvim-lsp.ui.symbols: present workspace/symbol results in the lvim-utils peek.
--
-- Queries `workspace/symbol` with the word under the cursor, maps SymbolInformation → peek items
-- grouped by file (each with its kind icon), and opens the peek with a filter bar built from the
-- symbol KINDS actually present ([A]ll + one button per kind). Mirrors ui/locations.lua.
--
---@module "lvim-lsp.ui.symbols"

local lsp_state = require("lvim-lsp.state")
local notify = require("lvim-ls.utils.notify")
local peek = require("lvim-utils.ui.peek")
local outline = require("lvim-lsp.ui.outline")

local SymbolKind = vim.lsp.protocol.SymbolKind

local M = {}

--- Open the workspace-symbols peek (`mode` = "split" | "float"). Query = the word under the cursor.
---@param mode string
function M.workspace(mode)
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
                local loc = s.location
                if loc and loc.uri then
                    local rng = loc.range
                    local icon, icon_hl = outline.kind_icon(s.kind)
                    items[#items + 1] = {
                        filename = vim.uri_to_fname(loc.uri),
                        lnum = (rng and rng.start.line or 0) + 1,
                        col = (rng and rng.start.character or 0) + 1,
                        text = s.name,
                        kind = s.kind,
                        icon = icon,
                        icon_hl = icon_hl,
                    }
                    kinds[s.kind] = true
                end
            end
        end
        if #items == 0 then
            notify("No workspace symbols for '" .. query .. "'.", vim.log.levels.INFO)
            return
        end

        -- Kind filter: [A]ll + one button per kind present (stable order by kind number). Kind buttons
        -- carry no hotkey (too many to letter uniquely) — reached by click or the `f` cycle.
        local buttons = {}
        buttons[1] = {
            id = "all",
            label = "All",
            key = "a",
            predicate = function()
                return true
            end,
        }
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

        peek.open({
            title = "Workspace Symbols",
            items = items,
            mode = mode,
            list_match = false, -- rows are symbol names, not source lines
            bar = { groups = { { id = "kind", active = "all", primary = true, buttons = buttons } } },
        }, { peek = (lsp_state.config.peek or {}).appearance })
    end)
end

return M
