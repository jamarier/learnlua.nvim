local M = {}

local function normalize(s)
  return tostring(s):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local validators = {
  path = function(result)
    local s = tostring(result)
    return s:match("^/") ~= nil or s:match("^%a:[/\\]") ~= nil
  end,
}

M.check = function(code_lines, expected)
  local code = table.concat(code_lines, "\n")
  local printed_lines = {}

  -- Capture helper — accumulates every print call
  local function capture_output(...)
    local parts = {}
    for i = 1, select("#", ...) do
      local v = select(i, ...)
      table.insert(parts, type(v) == "table" and vim.inspect(v) or tostring(v))
    end
    table.insert(printed_lines, table.concat(parts, "\t"))
  end

  local sandbox_table = {}
  for k, v in pairs(table) do
    sandbox_table[k] = v
  end
  sandbox_table.unpack = sandbox_table.unpack or _G.unpack
  -- Polyfill for table.pack (Missing in Lua 5.1/LuaJIT)
  sandbox_table.pack = function(...)
    return { n = select("#", ...), ... }
  end

  local sandbox = {
    vim = setmetatable({}, {
      __index = function(_, k)
        if k == "print" then
          return capture_output
        end
        return vim[k]
      end,
    }),
    _G = _G,
    print = capture_output,
    string = string,
    table = sandbox_table,
    math = math,
    io = io,
    os = os,
    tostring = tostring,
    tonumber = tonumber,
    type = type,
    pairs = pairs,
    ipairs = ipairs,
    next = next,
    select = select,
    pcall = pcall,
    error = error,
    assert = assert,
    load = load,
    rawget = rawget,
    rawset = rawset,
    setmetatable = setmetatable,
    getmetatable = getmetatable,
  }

  sandbox._G = sandbox
  setmetatable(sandbox, { __index = _G })

  local fn, err
  fn, err = load(code, "exercise", "t", sandbox)

  if not fn then
    return false, "Syntax error: " .. err, nil, {}
  end

  local ok, result = pcall(fn)
  if not ok then
    return false, "Runtime error: " .. tostring(result), nil, printed_lines
  end

  -- FALLBACK: Use last printed output if return is nil
  if result == nil and #printed_lines > 0 then
    result = printed_lines[#printed_lines]
  end

  -- Final stringify for tables
  if type(result) == "table" then
    result = vim.inspect(result)
  end

  -- Validation
  local validator = validators[expected]
  if validator then
    if validator(result) then
      return true, "Correct!", result, printed_lines
    else
      return false, "expected a " .. expected .. ', got "' .. tostring(result) .. '"', result, printed_lines
    end
  end

  if normalize(result) == normalize(expected) then
    return true, "Correct!", result, printed_lines
  else
    return false, 'expected "' .. expected .. '"', result, printed_lines
  end
end

return M
