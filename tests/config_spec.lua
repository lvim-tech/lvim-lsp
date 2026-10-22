-- The UI config every lvim-lsp reader holds a reference to.
--
-- Modules cache `require("lvim-lsp.state").config` at load time, so configure() must merge INTO
-- that table and never replace it — and the two function slots it carries (`build` / `force`) must
-- survive a merge that does not mention them, because a nil there is a crash at paint time.

local state = require("lvim-lsp.state")

describe("lvim-lsp.state.configure")

it("merges into the live table, so a cached reference stays live", function()
    local alias = state.config
    state.configure({ peek = { max_height = 42 } })
    eq(42, alias.peek.max_height)
    truthy(alias == state.config, "the table itself must not be replaced")
end)

it("leaves the keys it was not told about alone", function()
    local before = vim.deepcopy(state.config.peek)
    state.configure({ peek = { max_height = 11 } })
    for k, v in pairs(before) do
        if k ~= "max_height" and type(v) ~= "table" and type(v) ~= "function" then
            eq(v, state.config.peek[k], "peek." .. k .. " survived")
        end
    end
end)

it("keeps a callable build and force whatever it is given", function()
    state.configure({})
    truthy(type(state.config.build) == "function", "build must stay callable")
    truthy(state.config.force ~= nil, "force must stay set")
    state.configure({ build = nil, force = nil })
    truthy(type(state.config.build) == "function", "a merge that omits them restores the defaults")
    truthy(state.config.force ~= nil)
end)

it("takes no options at all", function()
    local ok, err = pcall(state.configure, nil)
    truthy(ok, tostring(err))
end)
