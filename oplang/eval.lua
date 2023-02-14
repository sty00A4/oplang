local lexer = require "oplang.lexer"
local parser = require "oplang.parser"

local function Context()
    return setmetatable(
        ---@class Context
        {
            scopes = { {} },
            ---@param self Context
            ---@param id string
            ---@return any
            get = function(self, id)
                for i = #self.scopes, 1, -1 do
                    if type(self.scopes[i][id]) ~= "nil" then
                        return self.scopes[i][id]
                    end
                end
            end,
            ---@param self Context
            ---@param id string
            ---@param value any
            set = function(self, id, value)
                if #self.scopes > 0 then
                    for i = #self.scopes, 1, -1 do
                        if type(self.scopes[i][id]) ~= "nil" then
                            self.scopes[i][id] = value
                            return
                        end
                    end
                    self.scopes[#self.scopes][id] = value
                end
            end,
            ---@param self Context
            ---@param id string
            ---@param value any
            create = function(self, id, value)
                if #self.scopes > 0 then
                    self.scopes[#self.scopes][id] = value
                end
            end,
            ---@param self Context
            ---@param id string
            ---@param value any
            global = function(self, id, value)
                if #self.scopes > 0 then
                    for i = #self.scopes, 1, -1 do
                        if type(self.scopes[i][id]) ~= "nil" then
                            self.scopes[i][id] = value
                            return
                        end
                    end
                    self.scopes[1][id] = value
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
---@param t table
local function isPos(t)
    if type(t) == "table" then
        local meta = getmetatable(t)
        if meta then
            if meta.__name == "position" then
                if type(t.ln) == "table" and type(t.col) == "table" then
                    return type(t.ln.start) == "number" and type(t.ln.stop) == "number" and
                    type(t.col.start) == "number" and type(t.col.stop) == "number"
                end
            end
        end
    end
    return false
end
---@param t table
local function isNode(t)
    if type(t) == "table" then
        local meta = getmetatable(t)
        if meta then
            return meta.__name == "node" and type(t.node) == "string" and isPos(t.pos)
        end
    end
    return false
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
    ["nil"] = function(node, context)
        return nil, "return"
    end,
    ---@param node Node
    ---@param context Context
    ---@return any, Return, string|nil, Position|nil
    closure = function(node, context)
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
                if args[2] then
                    if type(args[1]) ~= "number" then
                        return nil, nil, "bad argument #1 (expected number, got "..type(args[1])..")", node.pos
                    end
                    if type(args[2]) ~= "number" then
                        return nil, nil, "bad argument #2 (expected number, got "..type(args[2])..")", node.pos
                    end
                    return table.sub(value, args[1], args[2]), "return"
                end
                return value[args[1]], "return"
            end
            return value, "return"
        end
        if type(value) == "string" then
            if args[1] then
                if type(args[1]) ~= "number" then
                    return nil, nil, "bad argument #1 (expected number, got "..type(args[1])..")", node.pos
                end
                if args[2] then
                    if type(args[2]) ~= "number" then
                        return nil, nil, "bad argument #2 (expected number, got "..type(args[2])..")", node.pos
                    end
                    return value:sub(args[1], args[2]), "return"
                end
                return value:sub(args[1]), "return"
            end
            return value, "return"
        end
        if type(value) == "boolean" then
            return value and args[1] or args[2]
        end
        if type(value) == "number" then
            return args[value]
        end
        return nil, nil, "unsupported type for head ("..type(value)..")", head.pos
    end
}

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

    context:create("set", function(node, args, context)
        if type(args[1]) == "string" then
            context:set(args[1], args[2])
        else
            return nil, nil, "bad argument #1 (expected string, got "..type(args[1])..")", node.pos
        end
    end)
    context:create("create", function(node, args, context)
        if type(args[1]) == "string" then
            context:create(args[1], args[2])
        else
            return nil, nil, "bad argument #1 (expected string, got "..type(args[1])..")", node.pos
        end
    end)
    context:create("global", function(node, args, context)
        if type(args[1]) == "string" then
            context:global(args[1], args[2])
        else
            return nil, nil, "bad argument #1 (expected string, got "..type(args[1])..")", node.pos
        end
    end)
    context:create("func", function(node, args, context)
        local idx = 1
        local params = {}
        while type(args[idx]) == "string" do
            table.insert(params, args[idx])
            idx = idx + 1
        end
        if not isNode(args[idx]) then
            return nil, nil, "bad last argument (expected node table, got "..type(args[idx])..")", node.pos
        end
        local funcNode = args[idx]
        return function(_, args, context)
            for i, param in ipairs(params) do
                context:create(param, args[i])
            end
            local value, _, err, epos = eval(funcNode, context) if err then return nil, nil, err, epos end
            return value
        end, "return"
    end)

    context:create("table", function(_, args, _)
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
    context:create("array", function(_, args, _)
        local array = {}
        for _, arg in pairs(args) do
            table.insert(array, arg)
        end
        return array, "return"
    end)
    
    context:create("do", function(_, args, context)
        for _, arg in pairs(args) do
            if isNode(arg) then
                local value, ret, err, epos = eval(arg, context) if err then return nil, nil, err, epos end
                if ret then
                    return value, ret
                end
            else
                return arg, "return"
            end
        end
    end)
    
    context:create("string", function(_, args, _)
        return tostring(args[1]), "return"
    end)
    context:create("number", function(_, args, _)
        return tonumber(args[1]), "return"
    end)
    context:create("bool", function(_, args, _)
        if args[1] then
            return true, "return"
        end
        return false, "return"
    end)

    local stdPath ="oplang/std.op"
    local file = io.open(stdPath, "r")
    if file then
        local text = file:read("a")
        file:close()
        local tokens = lexer.lex(stdPath, text)
        local node, err, epos = parser.parse(tokens) if err and not node then
            error("ERROR: "..err)
        end
        local _, _, err, epos = eval(node, context) if err then
            error("ERROR: "..err)
        end
    end

    return context
end

return {
    eval = eval,
    Context = Context, STDContext = STDContext, NodeEval = NodeEval
}
