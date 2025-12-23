local M = {}

local config = nil

function M.setup(cfg)
  config = cfg
end

-- Get the path to the recent ticket file
local function get_recent_file_path()
  if not config or not config.cache_dir then
    return vim.fn.stdpath("cache") .. "/jira/recent_ticket.json"
  end
  return config.cache_dir .. "/recent_ticket.json"
end

-- Save the most recently opened ticket
function M.save_recent(issue_key)
  if not issue_key or issue_key == "" then
    return
  end
  
  local recent_file = get_recent_file_path()
  local recent_data = {
    key = issue_key,
    timestamp = os.time(),
  }
  
  local json_str = vim.fn.json_encode(recent_data)
  
  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(recent_file, ":h")
  vim.fn.mkdir(dir, "p")
  
  -- Write to file
  local file = io.open(recent_file, "w")
  if file then
    file:write(json_str)
    file:close()
  else
    vim.notify("Failed to save recent ticket", vim.log.levels.WARN)
  end
end

-- Get the most recently opened ticket
function M.get_recent()
  local recent_file = get_recent_file_path()
  
  -- Check if file exists
  if vim.fn.filereadable(recent_file) == 0 then
    return nil
  end
  
  -- Read file
  local file = io.open(recent_file, "r")
  if not file then
    return nil
  end
  
  local content = file:read("*a")
  file:close()
  
  if not content or content == "" then
    return nil
  end
  
  -- Parse JSON
  local ok, recent_data = pcall(vim.fn.json_decode, content)
  if not ok or not recent_data or not recent_data.key then
    return nil
  end
  
  return recent_data
end

return M

