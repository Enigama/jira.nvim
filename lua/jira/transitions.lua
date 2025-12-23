local M = {}

local config = nil

function M.setup(cfg)
  config = cfg
end

-- Get state dynamically to avoid stale references
local function get_state()
  return require("jira").state
end

-- Check if transition requires story points
local function requires_story_points(transition)
  if not transition.fields then return nil end
  
  -- Check for customfield story points (common field IDs)
  for field_key, field_info in pairs(transition.fields) do
    if field_key:match("^customfield_") and 
       field_info.name and 
       field_info.name:lower():match("story points") then
      return field_key, field_info.required
    end
  end
  return nil
end

-- Validate story points input
local function validate_story_points(input)
  if not input or input == "" then return nil end
  
  local num = tonumber(input)
  if not num then return nil, "Must be a number" end
  
  -- Allow 0, 0.25, 0.5, 1, 2, 3, etc.
  if num == 0 or num == 0.25 or num == 0.5 or (num >= 1 and num == math.floor(num)) then
    return num
  end
  
  return nil, "Must be 0, 0.25, 0.5, or a whole number >= 1"
end

-- Get available transitions for an issue
function M.get_available_transitions(issue_key)
  local api = require("jira.api")
  local response = api.get_transitions(issue_key)
  
  if response and response.status == 200 then
    local data = vim.fn.json_decode(response.body)
    return data.transitions or {}
  end
  
  return nil
end

-- Show transition picker and execute selected transition
-- @param issue_key string: The Jira issue key (e.g., "PROJ-123")
-- @param on_success function|nil: Optional callback called after successful transition
function M.show_transition_picker(issue_key, on_success)
  -- Authentication happens lazily in api.make_request()
  -- No need to check state.authenticated here
  
  vim.notify("Fetching available transitions...", vim.log.levels.INFO)
  
  local transitions = M.get_available_transitions(issue_key)
  
  if not transitions or #transitions == 0 then
    vim.notify("No transitions available for this issue", vim.log.levels.WARN)
    return
  end
  
  local transition_names = {}
  local transition_map = {}
  
  for _, transition in ipairs(transitions) do
    local name = transition.name
    table.insert(transition_names, name)
    transition_map[name] = transition
  end
  
  vim.ui.select(transition_names, {
    prompt = "Select transition for " .. issue_key .. ":",
  }, function(choice)
    if choice then
      local selected_transition = transition_map[choice]
      M.execute_transition(issue_key, selected_transition, on_success)
    end
  end)
end

-- Execute a transition with optional comment
-- @param issue_key string: The Jira issue key
-- @param transition table: The transition object
-- @param on_success function|nil: Optional callback called after successful transition
function M.execute_transition(issue_key, transition, on_success)
  local story_points_field, is_required = requires_story_points(transition)
  
  if story_points_field then
    -- Prompt for story points
    vim.ui.input({
      prompt = "Story points " .. (is_required and "(required)" or "(optional)") .. ": ",
      default = "",
    }, function(sp_input)
      if sp_input == nil then return end -- User cancelled
      
      local story_points, err = validate_story_points(sp_input)
      if sp_input ~= "" and not story_points then
        vim.notify("Invalid story points: " .. (err or "unknown error"), vim.log.levels.ERROR)
        return
      end
      
      -- If required but empty, reject
      if is_required and not story_points then
        vim.notify("Story points are required for this transition", vim.log.levels.ERROR)
        return
      end
      
      -- Ask for comment (existing flow)
      M.ask_for_comment(issue_key, transition, story_points_field, story_points, on_success)
    end)
  else
    -- No story points required, go to comment
    M.ask_for_comment(issue_key, transition, nil, nil, on_success)
  end
end

-- Handle comment input after story points
-- @param issue_key string: The Jira issue key
-- @param transition table: The transition object
-- @param sp_field_key string|nil: Story points field key if applicable
-- @param sp_value number|nil: Story points value if applicable
-- @param on_success function|nil: Optional callback called after successful transition
function M.ask_for_comment(issue_key, transition, sp_field_key, sp_value, on_success)
  vim.ui.input({
    prompt = "Add comment (optional): ",
    default = "",
  }, function(comment)
    if comment == nil then return end -- User cancelled
    
    -- Build fields object
    local fields = nil
    if sp_field_key and sp_value then
      fields = { [sp_field_key] = sp_value }
    end
    
    M.do_execute_transition(issue_key, transition.id, comment, fields, on_success)
  end)
end

-- Actually execute the transition
-- @param issue_key string: The Jira issue key
-- @param transition_id string: The transition ID
-- @param comment string|nil: Optional comment to add
-- @param fields table|nil: Optional fields to set (e.g., story points)
-- @param on_success function|nil: Optional callback called after successful transition
function M.do_execute_transition(issue_key, transition_id, comment, fields, on_success)
  local api = require("jira.api")
  
  vim.notify("Executing transition...", vim.log.levels.INFO)
  
  local response = api.do_transition(issue_key, transition_id, comment, fields)
  
  if response and response.status == 204 then
    vim.notify("Transition successful for " .. issue_key, vim.log.levels.INFO)
    -- Clear cache to force refresh
    api.cache.clear()
    -- Call success callback if provided
    if on_success and type(on_success) == "function" then
      on_success()
    end
    return true
  elseif response and response.status == 400 then
    local error_data = vim.fn.json_decode(response.body)
    local error_msg = "Transition failed"
    if error_data and error_data.errorMessages then
      error_msg = error_msg .. ": " .. table.concat(error_data.errorMessages, ", ")
    end
    vim.notify(error_msg, vim.log.levels.ERROR)
    return false
  else
    vim.notify("Transition failed for " .. issue_key, vim.log.levels.ERROR)
    return false
  end
end

return M

