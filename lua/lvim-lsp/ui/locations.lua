-- lvim-lsp.ui.locations: present LSP "go to / list locations" results in the lvim-utils PICKER.
--
-- The built-in handlers are reused via their `on_list` callback (so multi-client results are already
-- aggregated into quickfix-shaped items); we normalize those into picker items and open the public
-- finder (`lvim-picker`) with a file preview + jump. A single result jumps directly, matching the
-- native feel. Pure UI — the engine is untouched; which commands route here (and the layout) is decided
-- by `config.peek` in commands.lua.
--
-- Every peek (references / definitions / diagnostics …) is opened through lvim-picker under ONE stable dock
-- key (`DOCK_KEY`), so it is a SINGLE entry in the shared dock stack (`id = "lvim-picker:lsp-peek"`) that
-- lvim-picker routes through `dock.open` — one visible per layout (ZERO overlap with a docked picker /
-- terminal), cyclable with `<Leader>n`/`<Leader>p`, killable with `<Leader>x`, listed in `<Leader>m`. The
-- entry NAME follows the current peek's title (References / Definitions / …); its glyph is `config.peek.
-- appearance.icon`. Re-opening reuses (rebuilds) that one entry rather than stacking a new one per method.
--
---@module "lvim-lsp.ui.locations"

local lsp_state = require("lvim-lsp.state")
local notify = require("lvim-ls.utils.notify")
local picker = require("lvim-picker")

-- The shared dock-stack identity for EVERY location/diagnostics peek — a stable key so lvim-picker keeps a
-- single `lvim-picker:lsp-peek` entry (see diagnostics_list.lua, which reuses the same key on purpose).
---@type string
local DOCK_KEY = "lsp-peek"

local M = {}

-- method key → the built-in request, invoked with our `on_list` handler.
local REQUESTS = {
    references = function(on_list)
        vim.lsp.buf.references({ includeDeclaration = true }, { on_list = on_list })
    end,
    definition = function(on_list)
        vim.lsp.buf.definition({ on_list = on_list })
    end,
    type_definition = function(on_list)
        vim.lsp.buf.type_definition({ on_list = on_list })
    end,
    implementation = function(on_list)
        vim.lsp.buf.implementation({ on_list = on_list })
    end,
    declaration = function(on_list)
        vim.lsp.buf.declaration({ on_list = on_list })
    end,
}

local TITLES = {
    references = "References",
    definition = "Definitions",
    type_definition = "Type Definitions",
    implementation = "Implementations",
    declaration = "Declarations",
}

--- Jump to a location with `cmd` (edit/split/vsplit) and centre it.
---@param it table
---@param cmd? string
local function jump(it, cmd)
    cmd = cmd or "edit"
    if cmd == "edit" then
        -- `:edit` refuses with E37 when the current buffer has unsaved changes (the editable preview may be
        -- modified); `nvim_win_set_buf` swaps the file in without that.
        local buf = vim.fn.bufadd(it.path)
        vim.fn.bufload(buf)
        vim.api.nvim_win_set_buf(0, buf)
    else
        vim.cmd(cmd .. " " .. vim.fn.fnameescape(it.path))
    end
    pcall(vim.api.nvim_win_set_cursor, 0, { it.lnum, math.max(0, (it.col or 1) - 1) })
    vim.cmd("normal! zz")
end

--- Open `method`'s locations in the picker. `layout` = "area" | "float" | "bottom".
---@param method string
---@param layout string
function M.open(method, layout)
    local request = REQUESTS[method]
    if not request then
        return
    end
    request(function(res)
        local qf = (res and res.items) or {}
        if #qf == 0 then
            notify("No " .. (TITLES[method] or method):lower() .. " found.", vim.log.levels.INFO)
            return
        end
        local items = {}
        for _, e in ipairs(qf) do
            items[#items + 1] = {
                path = e.filename or (e.bufnr and vim.api.nvim_buf_get_name(e.bufnr)) or "",
                lnum = e.lnum or 1,
                col = e.col or 1,
                end_lnum = e.end_lnum,
                end_col = e.end_col,
                text = e.text,
            }
        end
        if #items == 1 then
            jump(items[1])
            return
        end
        local peek = lsp_state.config.peek or {}
        local appearance = peek.appearance or {}
        picker.open({
            title = res.title or TITLES[method] or method,
            layout = layout,
            -- The stable dock identity: ONE `lvim-picker:lsp-peek` entry for every peek, so lvim-picker routes
            -- it through `dock.open` (one visible per layout, no overlap) instead of a per-method entry.
            key = DOCK_KEY,
            -- config.peek.dock_stack: true = managed dock-stack consumer; false = geometry-only standalone open.
            dock_stack = peek.dock_stack ~= false,
            -- config.peek.force: per-layout ANCHORED geometry overrides (deep-merged over the global dock geometry).
            force = peek.force,
            -- Nerd glyph fronting the title + the peek's dock-menu entry (config.peek.appearance.icon).
            icon = appearance.icon,
            -- configurable via config.peek.appearance.list_wrap (default true): a match far right on a long
            -- code line stays visible (wrap, no "↳").
            list_wrap = appearance.list_wrap ~= false,
            items = items,
            -- a flat row: `tail:lnum  code` (the preview winbar carries the full path)
            format = function(it)
                local tail = vim.fn.fnamemodify(it.path, ":t")
                return ("%s:%d  %s"):format(tail, it.lnum, (it.text or ""):gsub("^%s+", ""))
            end,
            preview_file = true, -- the REAL file buffer in the preview — editable, jump-to on confirm
            subtitle = function(it) -- the focused file name, after the title in the statusline
                return vim.fn.fnamemodify(it.path, ":t")
            end,
            on_confirm = function(it)
                jump(it, "edit")
            end,
            keys = {
                {
                    key = "<C-x>",
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
    end)
end

return M
