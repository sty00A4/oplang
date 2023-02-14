---@param path string
---@return File
local function File(path)
    return setmetatable(
        ---@class File
        {
            path = path
        },
        {
            __name = "path",
            __tostring = function(self)
                return self.path
            end
        }
    )
end

---@param file File
---@param lnStart integer
---@param lnStop integer
---@param colStart integer
---@param colStop integer
---@return Position
local function Position(file, lnStart, lnStop, colStart, colStop)
    return setmetatable(
        ---@class Position
        {
            ln = { start = lnStart, stop = lnStop },
            col = { start = colStart, stop = colStop },
            file = file,
            ---@param self Position
            ---@return Position
            copy = function(self)
                return Position(self.file, self.ln.start, self.ln.stop, self.col.start, self.col.stop)
            end,
            ---@param self Position
            ---@param pos Position
            extend = function(self, pos)
                self.ln.stop = pos.ln.stop
                self.col.stop = pos.col.stop
            end
        },
        {
            __name = "position",
            __tostring = function(self)
                return tostring(file)..":"..self.ln.start..":"..self.col.start
            end
        }
    )
end

---@param token string
---@param value any
---@param pos Position
---@return Token
local function Token(token, value, pos)
    return setmetatable(
        ---@class Token
        {
            token = token, value = value, pos = pos,
        },
        {
            __name = "token",
            __tostring = function(self)
                return "["..self.token..":"..tostring(self.value).."]"
            end
        }
    )
end

---@param path string
---@param text string
---@return table
local function lex(path, text)
    local file = File(path)
    local tokens = {}
    local idx = 1
    local ln = 1
    local col = 1
    ---@return string
    local function char()
        return text:sub(idx, idx)
    end
    local function advance()
        idx = idx + 1
        col = col + 1
        if char() == "\n" then
            ln = ln + 1
            col = 1
        end
    end
    local function symbol(s)
        return s == "(" or s == ")" or s == "[" or s == "]" or s == "{" or s == "}" or s == "\"" or s == "@" or s == "#" or s == ";"
    end
    ---@return Token|nil
    local function next()
        while char():match("%s") and #char() > 0 do
            advance()
        end
        while char() == ";" and #char() > 0 do
            advance()
            while not char() == "\n" and #char() > 0 do
                advance()
            end
            while char():match("%s") do
                advance()
            end
        end
        if #char() == 0 then
            return
        end
        local pos = Position(file, ln, ln, col, col)
        if char() == "(" then
            advance()
            return Token("callIn", "(", pos)
        end
        if char() == ")" then
            advance()
            return Token("callOut", ")", pos)
        end
        if char() == "[" then
            advance()
            return Token("vecIn", "[", pos)
        end
        if char() == "]" then
            advance()
            return Token("vecOut", "]", pos)
        end
        if char() == "{" then
            advance()
            return Token("bodyIn", "{", pos)
        end
        if char() == "}" then
            advance()
            return Token("bodyOut", "}", pos)
        end
        if char() == "#" then
            advance()
            return Token("closure", "#", pos)
        end
        if char() == "\"" then
            advance()
            local str = ""
            while char() ~= "\"" and #char() > 0 do
                str = str..char()
                advance()
            end
            pos:extend(Position(file, ln, ln, col, col))
            advance()
            return Token("string", str, pos)
        end
        if char():match("%d") then
            local number = char()
            advance()
            while char():match("%d") and #char() > 0 do
                number = number..char()
                pos:extend(Position(file, ln, ln, col, col))
                advance()
            end
            if char() == "." then
                number = number..char()
                pos:extend(Position(file, ln, ln, col, col))
                advance()
                while char():match("%d") and #char() > 0 do
                    number = number..char()
                    pos:extend(Position(file, ln, ln, col, col))
                    advance()
                end
            end
            return Token("number", tonumber(number), pos)
        end
        if char() == "@" then
            advance()
            local id = ""
            while not char():match("%s") and #char() > 0 do
                if symbol(char()) then break end
                id = id..char()
                pos:extend(Position(file, ln, ln, col, col))
                advance()
            end
            if id == "true" or id == "false" then
                return Token("boolean", id == "true", pos)
            end
            if id == "nil" then
                return Token("nil", nil, pos)
            end
            return Token("key", id, pos)
        end
        local id = char()
        advance()
        while not char():match("%s") and #char() > 0 do
            if symbol(char()) then break end
            id = id..char()
            pos:extend(Position(file, ln, ln, col, col))
            advance()
        end
        if id == "true" or id == "false" then
            return Token("boolean", id == "true", pos)
        end
        return Token("id", id, pos)
    end
    while #char() > 0 do
        local token = next()
        if not token then
            break
        end
        table.insert(tokens, token)
    end
    return tokens
end

return {
    lex = lex,
    Token = Token, Position = Position, File = File,
}