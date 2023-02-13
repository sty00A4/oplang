local function Context()
    return setmetatable(
        ---@class Context
        {
            scopes = { {} },
            ---@param self Context
            ---@param id string
            ---@return any
            get = function(self, id)
                for _, scope in ipairs(self.scopes) do
                    if type(scope[id]) ~= "nil" then
                        return scope[id]
                    end
                end
            end,
            ---@param self Context
            ---@param id string
            ---@param value any
            set = function(self, id, value)
                if #self.scopes > 0 then
                    self.scopes[#self.scopes][id] = value
                end
            end,
            ---@param self Context
            push = function(self)
                table.insert(self.scopes, {})
            end,
            ---@param self Context
            ---@return table|nil
            pop = function(self)
                if #self.scopes > 1 then
                    return table.remove(self.scopes)
                end
            end,
        },
        {
            __name = "context"
        }
    )
end
---@return Context
local function STDContext()
    local context = Context()
    local fieldJoin = "-"
    ---@param func function
    ---@return function
    local function linkf(func)
        return function (node, args, _)
            local res = { pcall(func, table.unpack(args)) }
            if res[1] then

                table.remove(res, 1)
                if #res == 1 then
                    return res[1]
                end
                return res
            end
            return nil, nil, "from Lua: "..tostring(res[2]), node.pos
        end
    end
    ---@param value any
    ---@param prefix string|nil
    local function link(value, prefix)
        if type(value) == "table" then
            for k, v in pairs(value) do
                if k ~= "_ENV" and k ~= "_G" then
                    link(v, prefix and prefix..fieldJoin..k or k)
                end
            end
            return
        end
        if not prefix then prefix = "?" end
        if type(value) == "function" then
            context:set(prefix, linkf(value))
        else
            context:set(prefix, value)
        end
    end
    link(_G)
    context:set("set", function(node, args, context)
        if type(args[1]) == "string" then
            context:set(args[1], args[2])
        else
            return nil, nil, "bad argument #1 (expected string, got "..type(args[1])..")", node.pos
        end
    end)
    context:set("table", function(_, args, _)
        local idx = 1
        local t = {}
        while idx <= #args do
            local key = args[idx]
            idx = idx + 1
            local value = args[idx]
            idx = idx + 1
            t[key] = value
        end
        return t, "return"
    end)
    context:set("array", function(_, args, _)
        local array = {}
        for _, arg in pairs(args) do
            table.insert(array, arg)
        end
        return array, "return"
    end)
    return context
end

---@alias Return "return"|"break"|nil

local NodeEval
---@param node Node
---@param context Context
local function eval(node, context)
    if NodeEval[node.node] then
        return NodeEval[node.node](node, context)
    end
    return nil, nil, "unsupported node: "..tostring(node.node), node.pos
end
NodeEval = {
    ---@param node Node
    ---@param context Context
    ---@return any, Return, string|nil, Position|nil
    id = function(node, context)
        return context:get(node.attr), "return"
    end,
    ---@param node Node
    ---@param context Context
    ---@return any, Return, string|nil, Position|nil
    number = function(node, context)
        return node.attr, "return"
    end,
    ---@param node Node
    ---@param context Context
    ---@return any, Return, string|nil, Position|nil
    string = function(node, context)
        return node.attr, "return"
    end,
    ---@param node Node
    ---@param context Context
    ---@return any, Return, string|nil, Position|nil
    key = function(node, context)
        return node.attr, "return"
    end,
    ---@param node Node
    ---@param context Context
    ---@return any, Return, string|nil, Position|nil
    boolean = function(node, context)
        return node.attr, "return"
    end,
    ---@param node Node
    ---@param context Context
    ---@return any, Return, string|nil, Position|nil
    chunk = function(node, context)
        context:push()
        for _, n in ipairs(node.attr) do
            local value, ret, err, epos = eval(n, context) if err then return nil, nil, err, epos end
            if ret then
                if ret == "return" then
                    context:pop()
                    return value, ret
                end
            end
        end
        context:pop()
    end,
    ---@param node Node
    ---@param context Context
    ---@return any, Return, string|nil, Position|nil
    call = function(node, context)
        local head = node.attr.head
        local nargs = node.attr.args
        local args = {}
        for k, narg in pairs(nargs) do
            local err, epos
            args[k], _, err, epos = eval(narg, context) if err then return nil, nil, err, epos end
        end
        local value, _, err, epos = eval(head, context) if err then return nil, nil, err, epos end
        if type(value) == "function" then
            return value(node, args, context)
        end
        if type(value) == "table" then
            if args[1] then
                return value[args[1]], "return"
            else
                return value, "return"
            end
        end
        return nil, nil, "expected function|table for the head, got "..type(value), head.pos
    end
}

return {
    eval = eval,
    Context = Context, STDContext = STDContext, NodeEval = NodeEval
}
