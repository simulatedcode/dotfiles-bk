-- selene: allow(global_usage)

local M = {}

--- Gets the location of the caller.
---@return string Source file and line number.
function M.get_loc()
  local me = debug.getinfo(1, "S")
  local level = 2
  local info = debug.getinfo(level, "S")

  while info and (info.source == me.source or info.source == "@" .. vim.env.MYVIMRC or info.what ~= "Lua") do
    level = level + 1
    info = debug.getinfo(level, "S")
  end

  info = info or me
  local source = info.source:sub(2)
  source = vim.loop.fs_realpath(source) or source
  return source .. ":" .. info.linedefined
end

--- Dumps a value to a Neovim notification.
---@param value any The value to dump.
---@param opts? {loc:string} Optional parameters.
function M._dump(value, opts)
  opts = opts or {}
  opts.loc = opts.loc or M.get_loc()

  if vim.in_fast_event() then
    return vim.schedule(function()
      M._dump(value, opts)
    end)
  end

  opts.loc = vim.fn.fnamemodify(opts.loc, ":~:.")
  local msg = vim.inspect(value)

  vim.notify(msg, vim.log.levels.INFO, {
    title = "Debug: " .. opts.loc,
    on_open = function(win)
      vim.wo[win].conceallevel = 3
      vim.wo[win].concealcursor = ""
      vim.wo[win].spell = false
      local buf = vim.api.nvim_win_get_buf(win)

      -- Use safer pcall here, even though treesitter.start rarely fails.
      local ok, err = pcall(vim.treesitter.start, buf, "lua")
      if not ok then
        vim.bo[buf].filetype = "lua"
        print("Error starting treesitter: " .. (err or "Unknown"))
      end
    end,
  })
end

--- Dumps values to a Neovim notification.  Handles single values vs. lists.
---@param ... any Values to dump.
function M.dump(...)
  local args = { ... }

  local value
  if #args == 0 then
    value = nil -- No arguments provided.
  elseif #args == 1 then
    value = args[1] -- Single argument.
  else
    value = args -- Multiple arguments, treat as a table.
  end

  M._dump(value)
end

--- Finds extmark leaks across buffers and namespaces.
function M.extmark_leaks()
  local counts = {}
  local nsn = vim.api.nvim_get_namespaces()

  for name, ns in pairs(nsn) do
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local count = #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})

      if count > 0 then
        counts[#counts + 1] = {
          name = name,
          buf = buf,
          count = count,
          ft = vim.bo[buf].ft,
        }
      end
    end
  end

  table.sort(counts, function(a, b)
    return a.count > b.count
  end)

  M._dump(counts, { loc = "extmark_leaks()" }) -- Use _dump for consistency and location info
end

--- Estimates the size of a Lua value in bytes.
--- This is not a precise measurement, but a reasonable estimate.
---@param value any The value to estimate.
---@param visited table<any, true>? A table to track visited values (to prevent infinite recursion).
---@return number The estimated size in bytes.
local function estimateSize(value, visited)
  if value == nil then
    return 0
  end

  -- Initialize the visited table if not already done
  visited = visited or {}

  -- Handle already-visited value to avoid infinite recursion
  if visited[value] then
    return 0
  end
  visited[value] = true

  local bytes = 0
  local value_type = type(value)

  if value_type == "boolean" then
    bytes = 4
  elseif value_type == "number" then
    bytes = 8
  elseif value_type == "string" then
    bytes = string.len(value) + 24
  elseif value_type == "function" then
    bytes = 32 -- Base size for a function

    -- Add size of upvalues
    local i = 1
    while true do
      local name, upvalue = debug.getupvalue(value, i)
      if not name then
        break
      end
      bytes = bytes + estimateSize(upvalue, visited)
      i = i + 1
    end
  elseif value_type == "table" then
    bytes = 40 -- Base size for a table entry

    for k, v in pairs(value) do
      bytes = bytes + estimateSize(k, visited) + estimateSize(v, visited)
    end

    local mt = debug.getmetatable(value)
    if mt then
      bytes = bytes + estimateSize(mt, visited)
    end
  end

  return bytes
end

--- Identifies module leaks by estimating the size of loaded modules.
---@param filter string? Optional filter to match module names.
function M.module_leaks(filter)
  local sizes = {}

  for modname, mod in pairs(package.loaded) do
    if not filter or modname:match(filter) then
      local root = modname:match("^([^%.]+)%..*$") or modname

      if not sizes[root] then
        sizes[root] = { mod = root, size = 0 }
      end

      sizes[root].size = sizes[root].size + estimateSize(mod) / (1024 * 1024)
    end
  end

  local sizes_table = vim.tbl_values(sizes)
  table.sort(sizes_table, function(a, b)
    return a.size > b.size
  end)

  M._dump(sizes_table, { loc = "module_leaks()" }) -- Use _dump for consistency and location info
end

--- Retrieves an upvalue from a function by name.
---@param func function The function to inspect.
---@param name string The name of the upvalue to retrieve.
---@return any|nil The upvalue's value, or nil if not found.
function M.get_upvalue(func, name)
  local i = 1

  while true do
    local n, v = debug.getupvalue(func, i)
    if not n then
      break
    end

    if n == name then
      return v
    end

    i = i + 1
  end

  return nil
end

return M
