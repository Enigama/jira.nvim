local M = {}

local config = nil

function M.setup(cfg)
  config = cfg
end

-- Get state dynamically to avoid stale references
function M.get_state()
  return require("jira").state
end

function M.get_config()
  return config
end

-- Detect search type based on input
function M.detect_search_type(input)
  if not input or input == "" then
    return "all"
  end
  
  -- Check if it's a Jira key format (e.g., PROJ-123)
  if string.match(input, "^[A-Z]+-[0-9]+$") then
    return "key"
  end
  
  return "text"
end

-- Open URL in browser
function M.open_in_browser(url)
  local open_cmd
  if vim.fn.has("mac") == 1 then
    open_cmd = "open"
  elseif vim.fn.has("unix") == 1 then
    open_cmd = "xdg-open"
  elseif vim.fn.has("win32") == 1 then
    open_cmd = "start"
  else
    vim.notify("Unsupported platform for opening URLs", vim.log.levels.ERROR)
    return
  end
  
  vim.fn.jobstart({open_cmd, url}, {detach = true})
end

-- Copy URL to clipboard
function M.copy_to_clipboard(text)
  vim.fn.setreg("+", text)
end

return M

