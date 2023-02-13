local lang = require "oplang"
local args = {...}
if args[1] then
    term.clear() term.setCursorPos(1, 1)
    ---@type string
    local path = args[1]
    local file = fs.open(path, "r")
    if not file then
        print(("couldn't open path %q"):format(path))
        return
    end
    local text = file:readAll()
    file:close()
    local tokens = lang.lexer.lex(path, text)
    -- for _, token in ipairs(tokens) do io.write(tostring(token).." ") end print()
    local node, err, epos = lang.parser.parse(tokens) if err and not node then
        print("ERROR: "..err)
    end
    -- print(node:repr())
    local context = lang.eval.STDContext()
    local value, ret, err, epos = lang.eval.eval(node, context) if err then
        print("ERROR: "..err)
    end
end