table.sub = function(t, i, j)
    if type(t) ~= "table" then error("bad argument #1 (expected table, got "..type(t)..")") end
    if type(i) ~= "number" then error("bad argument #2 (expected number, got "..type(i)..")") end
    if not j then j = #t end
    if type(j) ~= "number" then error("bad argument #3 (expected number, got "..type(j)..")") end
    local subT = {}
    for idx = i, j do
        table.insert(subT, t[idx])
    end
    return subT
end
local lang = {}
lang.lexer = require "oplang.lexer"
lang.parser = require "oplang.parser"
lang.eval = require "oplang.eval"
return lang