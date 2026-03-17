-- lvim-lsp: form renderer for per-server settings.
-- Converts schema sections (from core/schema.lua) into a lvim-utils tabs form.
--
-- Each schema section becomes a tab.
-- Each field becomes a typed row: bool / select / int / string / list (action).
-- Two action rows at the bottom of every tab:
--   "Apply for session"   → on_apply_session(pending_settings)
--   "Apply permanently"   → on_apply_permanent(pending_settings)
--
-- `pending` is a shared deep copy of merged settings — all tabs write into it,
-- so changes accumulate across tabs before applying.
--
---@module "lvim-lsp.ui.form"

local schema_mod = require("lvim-lsp.core.schema")

local M = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────

--- Return true when t is a pure sequence (array).
local function is_list(t)
    if type(t) ~= "table" then return false end
    local i = 0
    for _ in pairs(t) do
        i = i + 1
        if t[i] == nil then return false end
    end
    return true
end

--- Compute the delta between `base` and `modified` (only changed/added values).
--- Arrays are treated atomically: if any element differs, the full new array is included.
---@param base     table
---@param modified table
---@return table
local function diff(base, modified)
    local result = {}
    for k, v in pairs(modified) do
        if type(v) == "table" and type(base[k]) == "table" then
            if is_list(v) then
                if not vim.deep_equal(base[k], v) then result[k] = v end
            else
                local sub = diff(base[k], v)
                if not vim.tbl_isempty(sub) then result[k] = sub end
            end
        elseif v ~= base[k] then
            result[k] = v
        end
    end
    return result
end

-- ── Row builders ──────────────────────────────────────────────────────────────

local function bool_row(field, pending)
    return {
        type  = "bool",
        name  = field.key,
        label = field.label,
        value = field.value,
        run   = function(val) schema_mod.set(pending, field.key, val) end,
    }
end

local function select_row(field, pending)
    return {
        type    = "select",
        name    = field.key,
        label   = field.label,
        value   = field.value,
        options = field.options,
        run     = function(val) schema_mod.set(pending, field.key, val) end,
    }
end

local function number_row(field, pending)
    return {
        type  = "int",
        name  = field.key,
        label = field.label,
        value = field.value,
        run   = function(val) schema_mod.set(pending, field.key, val) end,
    }
end

local function string_row(field, pending)
    return {
        type  = "string",
        name  = field.key,
        label = field.label,
        value = field.value,
        run   = function(val) schema_mod.set(pending, field.key, val) end,
    }
end

--- List type — string row with comma-separated value; s.render() fires automatically on edit.
local function list_row(field, pending)
    local joined = type(field.value) == "table" and table.concat(field.value, ", ") or (field.value or "")
    return {
        type  = "string",
        name  = field.key,
        label = field.label,
        value = joined,
        run   = function(val)
            local items = {}
            for item in val:gmatch("[^,]+") do
                local trimmed = vim.trim(item)
                if trimmed ~= "" then table.insert(items, trimmed) end
            end
            schema_mod.set(pending, field.key, items)
        end,
    }
end

local BUILDERS = {
    bool   = bool_row,
    select = select_row,
    number = number_row,
    string = string_row,
    list   = list_row,
}

-- ── Section → Tab ─────────────────────────────────────────────────────────────

--- Convert one schema section into a lvim-utils tab with rows.
---@param sec              LvimLspSchemaSection
---@param pending          table   shared mutable settings copy
---@param base             table   original merged settings (for diff on save)
---@param on_apply_session   fun(settings: table)
---@param on_apply_permanent fun(settings: table)
---@param stay             table   shared { value: boolean } — stay open after apply
---@param after_apply_default string  "Stay" | "Close"
---@return table  lvim-utils Tab
local function section_to_tab(sec, pending, base, on_apply_session, on_apply_permanent, stay, after_apply_default)
    local rows = {}

    for _, field in ipairs(sec.fields) do
        local builder = BUILDERS[field.type]
        if builder then
            table.insert(rows, builder(field, pending))
        else
            -- Unknown type — fallback to string row
            table.insert(rows, string_row(
                vim.tbl_extend("force", field, { type = "string" }),
                pending
            ))
        end
    end

    -- Spacer + stay toggle + apply buttons
    table.insert(rows, { type = "spacer_line" })
    table.insert(rows, {
        type    = "select",
        name    = "_after_apply",
        label   = "After Apply",
        value   = after_apply_default,
        options = { "Stay", "Close" },
        run     = function(val) stay.value = (val == "Stay") end,
    })
    table.insert(rows, { type = "spacer", label = "" })
    table.insert(rows, {
        type  = "action",
        label = "Apply for session",
        run   = function(_, close)
            on_apply_session(vim.deepcopy(pending))
            if not stay.value then close(true, pending) end
        end,
    })
    table.insert(rows, {
        type  = "action",
        label = "Apply permanently",
        run   = function(_, close)
            local delta = diff(base, pending)
            on_apply_permanent(delta, vim.deepcopy(pending))
            if not stay.value then close(true, pending) end
        end,
    })

    return { label = sec.section, rows = rows }
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Open a settings form for `server_name`.
---
---@param server_name        string
---@param root_dir           string
---@param bufnr              integer
---@param on_apply_session   fun(settings: table)
---@param on_apply_permanent fun(delta: table, full: table)
---@param on_back?           fun()  Called when user presses <BS> to return to parent panel
function M.open(server_name, root_dir, bufnr, on_apply_session, on_apply_permanent, on_back)
    local ui_mod = require("lvim-lsp.ui").get()
    if not ui_mod then
        vim.notify("lvim-lsp: lvim-utils is required for the settings form", vim.log.levels.ERROR)
        return
    end

    local sections, merged = schema_mod.resolve(server_name, root_dir, bufnr)
    if not sections or #sections == 0 then
        vim.notify("lvim-lsp: no settings found for " .. server_name, vim.log.levels.WARN)
        return
    end

    local state   = require("lvim-lsp.state")
    local keys_cfg = state.config.popup_global and state.config.popup_global.keys or {}
    local back_key = keys_cfg.back or "<BS>"

    -- Shared pending copy — all tabs write into this
    local pending = vim.deepcopy(merged)
    -- Base snapshot for diff on "Apply permanently"
    local base = vim.deepcopy(merged)
    -- Shared stay-open toggle (default from config)
    local after_apply_default = state.config.form and state.config.form.after_apply or "Stay"
    local stay = { value = after_apply_default == "Stay" }

    local tabs = {}
    for _, sec in ipairs(sections) do
        table.insert(tabs, section_to_tab(sec, pending, base, on_apply_session, on_apply_permanent, stay, after_apply_default))
    end

    ui_mod.tabs({
        title    = server_name .. " — Settings",
        tabs     = tabs,
        back_key = on_back and back_key or nil,
        on_open  = on_back and function(buf, _)
            vim.keymap.set("n", back_key, function()
                vim.api.nvim_feedkeys(
                    vim.api.nvim_replace_termcodes("q", true, false, true), "m", false)
            end, { buffer = buf, silent = true, nowait = true })
        end or nil,
        callback = on_back and function(confirmed, _)
            if not confirmed then on_back() end
        end or nil,
    })
end

return M
