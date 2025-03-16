local M = {}

function M.cowboy()
  -- Set of keys to monitor
  local keys = { "h", "j", "k", "l", "+", "-" }

  for _, key in ipairs(keys) do
    local count = 0 -- Number of times the key has been pressed
    local timer = vim.uv.new_timer() -- Create a timer to reset the count
    local original_map = key -- Store the original mapping for reset

    vim.keymap.set("n", key, function()
      if vim.v.count > 0 then
        count = 0
      end

      count = count + 1

      if count >= 10 and vim.bo.buftype ~= "nofile" then
        local ok, err = pcall(vim.notify, "Hold it Cowboy!", vim.log.levels.WARN, {
          icon = "🤠",
          id = "cowboy",
          keep = function()
            return count >= 10
          end,
        })

        if not ok then
          print("Error: " .. err) -- Print the error for debugging
          return original_map
        end
      else
        timer:start(2000, 0, function()
          count = 0
        end)
      end

      return original_map
    end, { expr = true, silent = true })
  end
end

return M
