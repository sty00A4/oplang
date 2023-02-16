local lexer = require "oplang.lexer"
local parser = require "oplang.parser"

local function Scope()
    return setmetatable(
        ---@class Scope
        {
            vars = {},
            defs = {},
            const = {},
            ---@param self Scope
            ---@param id string
            ---@param const boolean|nil
            ---@param value any
            set = function(self, id, value, const)
                self.vars[id] = value
                if not self:exist(id) then table.insert(self.defs, id) end
                self.const[id] = const
            end,
            ---@param self Scope
            ---@param id string
            get = function(self, id)
                return self.vars[id]
            end,
            ---@param self Scope
            ---@param id string
            exist = function(self, id)
                for _, reg in ipairs(self.defs) do
                    if reg == id then
                        return true
                    end
                end
                return false
            end,
            ---@param self Scope
            ---@param id string
            isConst = function(self, id)
                return self.const[id]
            end,
        },
        {
            __name = "scope"
        }
    )
end

local function Context()
    return setmetatable(
        ---@class Context
        {
            scopes = { Scope() }, traceback = {},
            ---@param self Context
            ---@param id string
            ---@return any
            get = function(self, id)
                for i = #self.scopes, 1, -1 do
                    if self.scopes[i]:exist(id) then
                        return self.scopes[i]:get(id)
                    end
                end
            end,
            ---@param self Context
            ---@param id string
            ---@return any
            isConst = function(self, id)
                for i = #self.scopes, 1, -1 do
                    if self.scopes[i]:exist(id) then
                        return self.scopes[i]:isConst(id)
                    end
                end
                return false
            end,
            ---@param self Context
            ---@param id string
            ---@param const boolean|nil
            ---@param value any
            ---@return string|nil
            set = function(self, id, value, const)
                if #self.scopes > 0 then
                    for i = #self.scopes, 1, -1 do
                        if self.scopes[i]:exist(id) then
                            if self.scopes[i]:isConst(id) then return "'"..id.."'".." is already defined as a constant" end
                            self.scopes[i]:set(id, value, const)
                            return
                        end
                    end
                    self.scopes[#self.scopes]:set(id, value)
                else
                    return "no scope to set variable in"
                end
            end,
            ---@param self Context
            ---@param id string
            ---@param const boolean|nil
            ---@param value any
            ---@return string|nil
            create = function(self, id, value, const)
                if #self.scopes > 0 then
                    for i = #self.scopes, 1, -1 do
                        if self.scopes[i]:isConst(id) then return "'"..id.."'".." is already defined as a constant" end
                    end
                    self.scopes[#self.scopes]:set(id, value, const)
                else
                    return "no scope to set variable in"
                end
            end,
            ---@param self Context
            ---@param id string
            ---@param const boolean|nil
            ---@param value any
            ---@return string|nil
            global = function(self, id, value, const)
                if #self.scopes > 0 then
                    for i = #self.scopes, 1, -1 do
                        if self.scopes[i]:exist(id) then
                            if self.scopes[i]:isConst(id) then return "'"..id.."'".." is already defined as a constant" end
                            self.scopes[i]:set(id, value, const)
                            return
                        end
                    end
                    self.scopes[1]:set(id, value)
                else
                    return "no scope to set variable in"
                end
            end,
            ---@param self Context
            ---@param pos Position
            push = function(self, pos)
                table.insert(self.traceback, pos)
                table.insert(self.scopes, Scope())
            end,
            ---@param self Context
            ---@return Scope|nil, Position|nil
            pop = function(self)
                if #self.scopes > 1 then
                    return table.remove(self.scopes), table.remove(self.traceback)
                end
            end,
            ---@param self Context
            trace = function(self)
                if #self.traceback > 0 then
                    local s = "Trace back (first on top):\n"
                    for _, pos in ipairs(self.traceback) do
                        s = s .. tostring(pos) .. "\n"
                    end
                    return s
                end
                return ""
            end
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
        context:push(node.pos)
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
    body = function(node, context)
        context:push(node.pos)
        for _, n in ipairs(node.attr) do
            local value, ret, err, epos = eval(n, context) if err then return nil, nil, err, epos end
            if ret then
                context:pop()
                return value, ret
            end
        end
        context:pop()
    end,
    ---@param node Node
    ---@param context Context
    ---@return any, Return, string|nil, Position|nil
    call = function(node, context)
        ---@type Node
        local head = node.attr.head
        ---@type table<integer, Node>
        local nargs = node.attr.args
        ---@type table<integer, any>
        local args = {}
        for k, narg in pairs(nargs) do
            local err, epos
            args[k], _, err, epos = eval(narg, context) if err then return nil, nil, err, epos end
        end
        local value, _, err, epos = eval(head, context) if err then return nil, nil, err, epos end
        if type(value) == "function" then
            local res, ret, err, epos = value(node, args, context) if err then return nil, nil, err, epos end
            return res, ret
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
            if value then
                return args[1]
            else
                return args[2]
            end
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
            if prefix then context:global(prefix, value, true) end
            for k, v in pairs(value) do
                link(v, prefix and prefix..fieldJoin..k or k)
            end
            return
        end
        if not prefix then prefix = "?" end
        if type(value) == "function" then
            context:global(prefix, linkf(value), true)
        else
            context:global(prefix, value, true)
        end
    end

    for _, prefix in ipairs({
        "assert", "bit32", "io", "coroutine", "debug", "getmetatable",
        "string", "table", "os", "next", "print", "pcall", "rawequal",
        "rawset", "rawget", "setmetatable", "tonumber", "tostring", "unpack",
        "utf8", "xpcall",
        "colors", "commands", "disk", "fs", "gps", "help", "http", "keys",
        "multishell", "paintutils", "parallel", "peripheral", "pocket", "rednet",
        "redstone", "settings", "shell", "term", "textutils", "turtle", "vector",
        "window"
    }) do
        link(_G[prefix], prefix)
    end
    math.round = function(x)
        if x - math.abs(x) >= 0.5 then
            return math.ceil(x)
        else
            return math.floor(x)
        end
    end
    if math then
        for prefix, v in pairs(math) do
            link(v, prefix)
        end
    end

    local add = linkf(function(a, b)
        return a + b
    end)
    local sub = linkf(function(a, b)
        return a - b
    end)
    local neg = linkf(function(a)
        return -a
    end)
    local mul = linkf(function(a, b)
        return a * b
    end)
    local div = linkf(function(a, b)
        return a / b
    end)
    local mod = linkf(function(a, b)
        return a % b
    end)
    local pow = linkf(function(a, b)
        return a ^ b
    end)
    local concat = linkf(function(a, b)
        return a .. b
    end)
    local eq = linkf(function(a, b)
        return a == b
    end)
    local ne = linkf(function(a, b)
        return a ~= b
    end)
    local lt = linkf(function(a, b)
        return a < b
    end)
    local le = linkf(function(a, b)
        return a <= b
    end)
    local gt = linkf(function(a, b)
        return a > b
    end)
    local ge = linkf(function(a, b)
        return a >= b
    end)
    local len = linkf(function(a)
        return #a
    end)
    local newIndex = linkf(function(a, b, c)
        a[b] = c
    end)

    context:create("+", function (node, args, context)
        local sum
        for _, arg in pairs(args) do
            local err, epos
            if sum then
                sum, _, err, epos = add(node, { sum, arg }, context) if err then return nil, nil, err, epos end
            else
                sum = arg
            end
        end
        return sum, "return"
    end)
    context:create("-", function (node, args, context)
        if #args == 1 then
            local n, _, err, epos = neg(node, args, context) if err then return nil, nil, err, epos end
            return n, "return"
        end
        local sum
        for _, arg in pairs(args) do
            local err, epos
            if sum then
                sum, _, err, epos = sub(node, { sum, arg }, context) if err then return nil, nil, err, epos end
            else
                sum = arg
            end
        end
        return sum, "return"
    end)
    context:create("*", function (node, args, context)
        local sum
        for _, arg in pairs(args) do
            local err, epos
            if sum then
                sum, _, err, epos = mul(node, { sum, arg }, context) if err then return nil, nil, err, epos end
            else
                sum = arg
            end
        end
        return sum, "return"
    end)
    context:create("/", function (node, args, context)
        local sum
        for _, arg in pairs(args) do
            local err, epos
            if sum then
                sum, _, err, epos = div(node, { sum, arg }, context) if err then return nil, nil, err, epos end
            else
                sum = arg
            end
        end
        return sum, "return"
    end)
    context:create("%", function (node, args, context)
        local sum
        for _, arg in pairs(args) do
            local err, epos
            if sum then
                sum, _, err, epos = mod(node, { sum, arg }, context) if err then return nil, nil, err, epos end
            else
                sum = arg
            end
        end
        return sum, "return"
    end)
    context:create("^", function (node, args, context)
        if #args == 1 then
            return pow(node, { args[1], args[1] }, context)
        end
        local sum
        for _, arg in pairs(args) do
            local err, epos
            if sum then
                sum, _, err, epos = pow(node, { sum, arg }, context) if err then return nil, nil, err, epos end
            else
                sum = arg
            end
        end
        return sum, "return"
    end)
    context:create("..", function (node, args, context)
        local sum
        for _, arg in pairs(args) do
            local err, epos
            if sum then
                sum, _, err, epos = concat(node, { sum, arg }, context) if err then return nil, nil, err, epos end
            else
                sum = arg
            end
        end
        return sum, "return"
    end)
    context:create("=", function (node, args, context)
        if #args <= 1 then
            return false
        end
        for i = 1, #args - 1 do
            local res, _, err, epos = eq(node, { args[i], args[i+1] }, context) if err then return nil, nil, err, epos end
            if not res then return false, "return" end
        end
        return true, "return"
    end)
    context:create("!=", function (node, args, context)
        if #args <= 1 then
            return false
        end
        for i = 1, #args - 1 do
            local res, _, err, epos = ne(node, { args[i], args[i+1] }, context) if err then return nil, nil, err, epos end
            if not res then return false, "return" end
        end
        return true, "return"
    end)
    context:create("<", function (node, args, context)
        if #args <= 1 then
            return false
        end
        for i = 1, #args - 1 do
            local res, _, err, epos = lt(node, { args[i], args[i+1] }, context) if err then return nil, nil, err, epos end
            if not res then return false, "return" end
        end
        return true, "return"
    end)
    context:create("<=", function (node, args, context)
        if #args <= 1 then
            return false
        end
        for i = 1, #args - 1 do
            local res, _, err, epos = le(node, { args[i], args[i+1] }, context) if err then return nil, nil, err, epos end
            if not res then return false, "return" end
        end
        return true, "return"
    end)
    context:create(">", function (node, args, context)
        if #args <= 1 then
            return false
        end
        for i = 1, #args - 1 do
            local res, _, err, epos = gt(node, { args[i], args[i+1] }, context) if err then return nil, nil, err, epos end
            if not res then return false, "return" end
        end
        return true, "return"
    end)
    context:create(">=", function (node, args, context)
        if #args <= 1 then
            return false
        end
        for i = 1, #args - 1 do
            local res, _, err, epos = ge(node, { args[i], args[i+1] }, context) if err then return nil, nil, err, epos end
            if not res then return false, "return" end
        end
        return true, "return"
    end)
    context:create("len", function (node, args, context)
        local res, _, err, epos = len(node, args, context) if err then return nil, nil, err, epos end
        return res, "return"
    end)

    context:create("get", function(node, args, context)
        if type(args[1]) == "string" then
            return context:get(args[1])
        end
        return nil, nil, "bad argument #1 (expected string, got "..type(args[1])..")", node.pos
    end)
    context:create("set", function(node, args, context)
        if type(args[1]) == "string" then
            local err = context:set(args[1], args[2]) if err then return nil, nil, err, node.pos end
            return
        end
        return nil, nil, "bad argument #1 (expected string, got "..type(args[1])..")", node.pos
    end)
    context:create("const", function(node, args, context)
        if type(args[1]) == "string" then
            local err = context:set(args[1], args[2], true) if err then return nil, nil, err, node.pos end
            return
        end
        return nil, nil, "bad argument #1 (expected string, got "..type(args[1])..")", node.pos
    end)
    context:create("seti", function(node, args, context)
        if type(args[1]) == "table" then
            local _, _, err, epos = newIndex(node, args, context) if err then return nil, nil, err, epos end
            return
        end
        return nil, nil, "bad argument #1 (expected table, got "..type(args[1])..")", node.pos
    end)
    context:create("create", function(node, args, context)
        if type(args[1]) == "string" then
            context:create(args[1], args[2])
            return
        end
        return nil, nil, "bad argument #1 (expected string, got "..type(args[1])..")", node.pos
    end)
    context:create("create-const", function(node, args, context)
        if type(args[1]) == "string" then
            context:create(args[1], args[2], true)
            return
        end
        return nil, nil, "bad argument #1 (expected string, got "..type(args[1])..")", node.pos
    end)
    context:create("global", function(node, args, context)
        if type(args[1]) == "string" then
            context:global(args[1], args[2])
            return
        end
        return nil, nil, "bad argument #1 (expected string, got "..type(args[1])..")", node.pos
    end)
    context:create("global-const", function(node, args, context)
        if type(args[1]) == "string" then
            context:global(args[1], args[2], true)
            return
        end
        return nil, nil, "bad argument #1 (expected string, got "..type(args[1])..")", node.pos
    end)
    context:create("func", function(node, args, _)
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
        ---@param node Node
        ---@param args table
        ---@param context Context
        ---@return any, nil, string|nil, Position|nil
        return function(node, args, context)
            context:push(node.pos)
            for i, param in ipairs(params) do
                context:create(param, args[i])
            end
            local value, _, err, epos = eval(funcNode, context) if err then return nil, nil, err, epos end
            context:pop()
            return value
        end, "return"
    end)
    context:create("func-inline", function(node, args, _)
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
        ---@param args table
        ---@param context Context
        ---@return any, Return, string|nil, Position|nil
        return function(_, args, context)
            for i, param in ipairs(params) do
                context:create(param, args[i])
            end
            local value, ret, err, epos = eval(funcNode, context) if err then return nil, nil, err, epos end
            return value, ret
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
    
    context:create("do", function(node, args, context)
        context:push(node.pos)
        for _, arg in pairs(args) do
            if isNode(arg) then
                local value, ret, err, epos = eval(arg, context) if err then return nil, nil, err, epos end
                if ret then
                    context:pop()
                    return value, ret
                end
            else
                context:pop()
                return arg, "return"
            end
        end
        context:pop()
    end)
    context:create("for", function(node, args, context)
        local key, value, iterator, closure = table.unpack(args)
        if type(key) ~= "string" then
            return nil, nil, "bad argument #1 (expected string, got "..type(key)..")", node.pos
        end
        if type(value) ~= "string" then
            return nil, nil, "bad argument #2 (expected string, got "..type(value)..")", node.pos
        end
        if type(iterator) ~= "table" then
            return nil, nil, "bad argument #3 (expected table, got "..type(iterator)..")", node.pos
        end
        if not isNode(closure) then
            return nil, nil, "bad argument #4 (expected node table, got "..type(closure)..")", node.pos
        end
        for k, v in pairs(iterator) do
            context:push(node.pos)
            context:create(key, k)
            context:create(value, v)
            local value, ret, err, epos = eval(closure, context) if err then return nil, nil, err, epos end
            context:pop() 
            if ret == "return" then
                return value, ret
            end
            if ret == "break" then
                break
            end
        end
    end)
    context:create("fori", function(node, args, context)
        local key, value, iterator, closure = table.unpack(args)
        if type(key) ~= "string" then
            return nil, nil, "bad argument #1 (expected string, got "..type(key)..")", node.pos
        end
        if type(value) ~= "string" then
            return nil, nil, "bad argument #2 (expected string, got "..type(value)..")", node.pos
        end
        if type(iterator) ~= "table" then
            return nil, nil, "bad argument #3 (expected table, got "..type(iterator)..")", node.pos
        end
        if not isNode(closure) then
            return nil, nil, "bad argument #4 (expected node table, got "..type(closure)..")", node.pos
        end
        for k, v in ipairs(iterator) do
            context:push(node.pos)
            context:create(key, k)
            context:create(value, v)
            local value, ret, err, epos = eval(closure, context) if err then return nil, nil, err, epos end
            context:pop() 
            if ret == "return" then
                return value, ret
            end
            if ret == "break" then
                break
            end
        end
    end)
    context:create("forn", function(node, args, context)
        local id, start, stop = table.unpack(args)
        if type(id) ~= "string" then
            return nil, nil, "bad argument #1 (expected string, got "..type(id)..")", node.pos
        end
        if type(start) ~= "number" then
            return nil, nil, "bad argument #2 (expected number, got "..type(start)..")", node.pos
        end
        if type(stop) ~= "number" then
            return nil, nil, "bad argument #3 (expected number, got "..type(stop)..")", node.pos
        end
        local step = 1
        local closure = args[4]
        if type(closure) == "number" then
            step = closure
            closure = args[5]
        end
        if not isNode(closure) then
            return nil, nil, "bad argument #4 (expected node table, got "..type(closure)..")", node.pos
        end
        for i = start, stop, step do
            context:push(node.pos)
            context:create(id, i)
            local value, ret, err, epos = eval(closure, context) if err then return nil, nil, err, epos end
            context:pop()
            if ret == "return" then
                return value, ret
            end
            if ret == "break" then
                break
            end
        end
    end)
    context:create("while", function(node, args, context)
        local condn, closure = table.unpack(args)
        if not isNode(condn) then
            return nil, nil, "bad argument #1 (expected node table, got "..type(condn)..")", node.pos
        end
        if not isNode(closure) then
            return nil, nil, "bad argument #2 (expected node table, got "..type(closure)..")", node.pos
        end
        local cond, _, err, epos = eval(condn, context) if err then return nil, nil, err, epos end
        while cond do
            context:push(node.pos)
            local value, ret, err, epos = eval(closure, context) if err then return nil, nil, err, epos end
            if ret == "return" then
                context:pop()
                return value, ret
            end
            if ret == "break" then
                context:pop()
                break
            end
            cond, _, err, epos = eval(condn, context) if err then return nil, nil, err, epos end
            context:pop()
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

    context:create("type", function (_, args, _)
        if type(args[1]) == "nil" then
            return "nil"
        end
        return type(args[1])
    end)
    
    context:create("error", function (node, args, context)
        return nil, nil, tostring(args[1]), node.pos
    end)

    local stdPath = "oplang/std.op"
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
