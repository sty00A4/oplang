local lexer = require "oplang.lexer"
local Position = lexer.Position

local NodeRepr
---@param node Node
---@return string
local function reprNode(node)
    if NodeRepr[node.node] then
        return NodeRepr[node.node](node)
    end
    return "?"
end
NodeRepr = {
    ---@param node Node
    chunk = function (node)
        local s = ""
        for _, n in ipairs(node.attr) do
            s = s .. reprNode(n) .. "\n"
        end
        return s
    end,
    ---@param node Node
    id = function (node)
        return node.attr
    end,
    ---@param node Node
    number = function (node)
        return tostring(node.attr)
    end,
    ---@param node Node
    string = function (node)
        return ("%q"):format(node.attr)
    end,
    ---@param node Node
    call = function (node)
        local s = "( "..reprNode(node.attr.head).." "
        for _, arg in ipairs(node.attr.args) do
            s = s .. reprNode(arg) .. " "
        end
        return s..")"
    end,
}

---@param node string
---@param attr any
---@param pos Position
---@return Node
local function Node(node, attr, pos)
    return setmetatable(
        ---@class Node
        {
            node = node, attr = attr, pos = pos,
            ---@param self Node
            repr = function(self)
                return reprNode(self)
            end
        },
        {
            __name = "node",
        }
    )
end


local function parse(tokens)
    local idx = 0
    local function advance()
        idx = idx + 1
    end
    advance()
    ---@return Token|nil
    local function get()
        return tokens[idx]
    end
    local body
    ---@return Node|nil, string|nil, Position|nil
    local function next()
        local token = get()
        if not token then
            return nil, "unexpected end of input"
        end
        if token.token == "callIn" then
            local pos = token.pos:copy()
            advance()
            local head, err, epos = next() if err and not head then return nil, err, epos end
            local args = body("callOut")
            pos:extend(get().pos)
            advance()
            return Node("call", { head = head, args = args }, pos), nil
        end
        if token.token == "id" or token.token == "number" or token.token == "string" or token.token == "key" or token.token == "boolean" then
            advance()
            return Node(token.token, token.value, token.pos), nil
        end
    end
    ---@param stopToken string|nil
    ---@return table|nil, string|nil, Position|nil
    function body(stopToken)
        local nodes = {}
        local token = get()
        if not token then
            return nil, "unexpected end of input"
        end
        local pos = token.pos:copy()
        while get() do
            local token = get()
            if not token then
                if stopToken then
                    return nil, "unexpected end of input, expected token: "..stopToken
                end
                break
            end
            if stopToken then if token.token == stopToken then break end end
            local node, err, epos = next() if err then return nil, err, epos end
            if not node then break end
            pos:extend(node.pos)
            table.insert(nodes, node)
        end
        return nodes
    end
    return Node("chunk", body())
end

return {
    parse = parse,
    Node = Node
}