local M = {}

local config = nil
local utils = require("jira.ui.utils")

function M.setup(cfg)
  config = cfg
end

-- Show copy menu with multiple format options
function M.show_copy_menu(issue)
  local key = issue.key
  local summary = issue.fields.summary or "No summary"
  local url = config.jira_url .. "/browse/" .. key
  
  local options = {
    "1. Ticket key only (" .. key .. ")",
    "2. Full URL (" .. url .. ")",
    "3. Markdown link ([" .. key .. "](" .. url .. "))",
    "4. Ticket title (" .. summary .. ")",
    "5. Key + Title (" .. key .. " - " .. summary .. ")",
    "6. Slack format (<" .. url .. "|" .. key .. ">)",
  }
  
  vim.ui.select(options, {
    prompt = "Select copy format:",
  }, function(choice)
    if not choice then
      return
    end
    
    local text_to_copy
    if choice:match("^1%.") then
      text_to_copy = key
    elseif choice:match("^2%.") then
      text_to_copy = url
    elseif choice:match("^3%.") then
      text_to_copy = "[" .. key .. "](" .. url .. ")"
    elseif choice:match("^4%.") then
      text_to_copy = summary
    elseif choice:match("^5%.") then
      text_to_copy = key .. " - " .. summary
    elseif choice:match("^6%.") then
      text_to_copy = "<" .. url .. "|" .. key .. ">"
    end
    
    if text_to_copy then
      utils.copy_to_clipboard(text_to_copy)
    end
  end)
end

-- Assign issue to current user
function M.assign_to_self(issue_key)
  local state = utils.get_state()
  if not state.current_user or not state.current_user.accountId then
    vim.notify("Current user information not available", vim.log.levels.ERROR)
    return
  end
  
  local api = require("jira.api")
  vim.notify("Assigning " .. issue_key .. " to yourself...", vim.log.levels.INFO)
  
  local response = api.assign_issue(issue_key, state.current_user.accountId)
  
  if response and response.status == 204 then
    vim.notify("Successfully assigned " .. issue_key .. " to you", vim.log.levels.INFO)
    api.cache.clear()
    return true
  else
    vim.notify("Failed to assign " .. issue_key, vim.log.levels.ERROR)
    return false
  end
end

return M

