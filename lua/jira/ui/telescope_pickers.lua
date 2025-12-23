local M = {}

local config = nil
local utils = require("jira.ui.utils")
local format = require("jira.ui.format")
local menus = require("jira.ui.menus")

function M.setup(cfg)
  config = cfg
end

-- Main search function with Telescope
function M.search_issues(opts)
  opts = opts or {}
  
  -- Authentication happens lazily in api.make_request()
  -- No need to check state.authenticated here
  
  -- Lazy load telescope modules
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    vim.notify("Telescope not found. Please install telescope.nvim", vim.log.levels.ERROR)
    return
  end
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")
  
  -- Show mode selector first
  local modes = {
    "All Issues",
    "Search by Key",
    "Search by Assignee",
    "Search by Text",
    "Search by Project",
    "My Issues",
  }
  
  vim.ui.select(modes, {
    prompt = "Select search mode:",
  }, function(choice)
    if not choice then
      return
    end
    
    local search_mode = choice
    
    -- Get search input based on mode
    local function perform_search(input)
      local api = require("jira.api")
      local jql
      
      if search_mode == "All Issues" then
        jql = api.jql.all_issues()
      elseif search_mode == "Search by Key" then
        if not input or input == "" then
          vim.notify("Please enter an issue key", vim.log.levels.WARN)
          return
        end
        jql = api.jql.by_key(input)
      elseif search_mode == "Search by Assignee" then
        if not input or input == "" then
          vim.notify("Please enter an assignee name", vim.log.levels.WARN)
          return
        end
        
        -- Search for users first
        local user_response = api.search_users(input)
        
        if not user_response or user_response.status ~= 200 then
          vim.notify("Failed to search users", vim.log.levels.ERROR)
          return
        end
        
        local users = vim.fn.json_decode(user_response.body)
        
        if not users or #users == 0 then
          vim.notify("No users found matching: " .. input, vim.log.levels.WARN)
          return
        end
        
        -- If only one user found, use it directly
        if #users == 1 then
          jql = api.jql.by_account_id(users[1].accountId)
        else
          -- Multiple users found, show picker
          local user_options = {}
          local user_map = {}
          for _, user in ipairs(users) do
            local display = string.format("%s (%s)", user.displayName, user.emailAddress or "no email")
            table.insert(user_options, display)
            user_map[display] = user.accountId
          end
          
          vim.ui.select(user_options, {
            prompt = "Select user:",
          }, function(choice)
            if not choice then return end
            
            local account_id = user_map[choice]
            local user_jql = api.jql.by_account_id(account_id)
            
            -- Check cache
            local cached_issues = api.cache.get_cached_issues(user_jql)
            if cached_issues then
              M.show_issue_picker(cached_issues, user_jql)
              return
            end
            
            -- Execute the search with selected user
            local response = api.search_issues(user_jql)
            
            if not response or response.status ~= 200 then
              vim.notify("Failed to search issues", vim.log.levels.ERROR)
              return
            end
            
            local data = vim.fn.json_decode(response.body)
            local issues = data.issues or {}
            api.cache.set_cached_issues(user_jql, issues)
            M.show_issue_picker(issues, user_jql)
          end)
          return -- Exit early since we handle the search in the callback
        end
      elseif search_mode == "Search by Text" then
        if not input or input == "" then
          vim.notify("Please enter search text", vim.log.levels.WARN)
          return
        end
        jql = api.jql.by_text(input)
      elseif search_mode == "Search by Project" then
        if not input or input == "" then
          vim.notify("Please enter a project key", vim.log.levels.WARN)
          return
        end
        jql = api.jql.by_project(input)
      elseif search_mode == "My Issues" then
        jql = api.jql.my_issues()
      end
      
      -- Check cache
      local cached_issues = api.cache.get_cached_issues(jql)
      
      if cached_issues then
        M.show_issue_picker(cached_issues, jql)
        return
      end
      
      -- Fetch issues
      vim.notify("Searching Jira issues...", vim.log.levels.INFO)
      local response = api.search_issues(jql)
      
      if not response or response.status ~= 200 then
        local error_msg = "Failed to search issues"
        if response then
          error_msg = error_msg .. " (HTTP " .. response.status .. ")"
          if response.body and response.body ~= "" then
            -- Try to parse error details
            local ok, error_data = pcall(vim.fn.json_decode, response.body)
            if ok and error_data.errorMessages then
              error_msg = error_msg .. ": " .. table.concat(error_data.errorMessages, ", ")
            elseif ok and error_data.errors then
              local errors = {}
              for k, v in pairs(error_data.errors) do
                table.insert(errors, k .. ": " .. v)
              end
              error_msg = error_msg .. ": " .. table.concat(errors, ", ")
            else
              error_msg = error_msg .. ": " .. response.body:sub(1, 100)
            end
          end
        end
        vim.notify(error_msg, vim.log.levels.ERROR)
        return
      end
      
      local data = vim.fn.json_decode(response.body)
      local issues = data.issues or {}
      
      -- Cache results
      api.cache.set_cached_issues(jql, issues)
      
      M.show_issue_picker(issues, jql)
    end
    
    -- Show input prompt if needed
    if search_mode == "All Issues" or search_mode == "My Issues" then
      perform_search("")
    else
      vim.ui.input({
        prompt = "Enter " .. search_mode:lower() .. ": ",
        default = "",
      }, function(input)
        if input then
          perform_search(input)
        end
      end)
    end
  end)
end

-- Show Telescope picker with issues
function M.show_issue_picker(issues, jql)
  -- Lazy load telescope modules
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    vim.notify("Telescope not found. Please install telescope.nvim", vim.log.levels.ERROR)
    return
  end
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")
  
  if #issues == 0 then
    vim.notify("No issues found", vim.log.levels.INFO)
    return
  end
  
  vim.notify("Found " .. #issues .. " issues", vim.log.levels.INFO)
  
  pickers.new({}, {
    prompt_title = "Jira Issues",
    finder = finders.new_table({
      results = issues,
      entry_maker = function(entry)
        return {
          value = entry,
          display = format.format_issue_entry(entry),
          ordinal = entry.key .. " " .. entry.fields.summary,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = M.create_issue_previewer(),
    attach_mappings = function(prompt_bufnr, map)
      M.attach_issue_mappings(prompt_bufnr, map, jql)
      return true
    end,
  }):find()
end

-- Create issue previewer
function M.create_issue_previewer()
  -- Lazy load telescope modules
  local ok, previewers = pcall(require, "telescope.previewers")
  if not ok then
    return nil
  end
  
  return previewers.new_buffer_previewer({
    title = "Issue Preview",
    define_preview = function(self, entry, status)
      local issue = entry.value
      local api = require("jira.api")
      
      -- Try to get from cache first
      local cached_issue = api.cache.get_cached_issue(issue.key)
      if cached_issue then
        local success, preview_lines = pcall(format.format_issue_as_markdown, cached_issue)
        if success and preview_lines and #preview_lines > 0 then
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview_lines)
          vim.bo[self.state.bufnr].filetype = "markdown"
        else
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {"Failed to format cached issue"})
        end
        return
      end
      
      -- Fetch full issue details
      local response = api.get_issue(issue.key)
      if response and response.status == 200 then
        local full_issue = vim.fn.json_decode(response.body)
        api.cache.set_cached_issue(issue.key, full_issue)
        local success, preview_lines = pcall(format.format_issue_as_markdown, full_issue)
        if success and preview_lines and #preview_lines > 0 then
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview_lines)
          vim.bo[self.state.bufnr].filetype = "markdown"
        else
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {"Failed to format issue"})
        end
      else
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {"Failed to load issue details"})
      end
    end,
  })
end

-- Attach issue mappings to telescope picker
-- @param prompt_bufnr number: The telescope prompt buffer number
-- @param map function: The telescope map function
-- @param jql string|nil: Optional JQL used to fetch issues (for refresh after transition)
function M.attach_issue_mappings(prompt_bufnr, map, jql)
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local buffer = require("jira.ui.buffer")
  
  -- Default action: open in buffer
  actions.select_default:replace(function()
    local selection = action_state.get_selected_entry()
    actions.close(prompt_bufnr)
    buffer.open_issue_in_buffer(selection.value)
  end)
  
  -- Copy with format menu
  map("i", "<C-y>", function()
    local selection = action_state.get_selected_entry()
    if selection then
      menus.show_copy_menu(selection.value)
    end
  end)
  
  map("n", "<C-y>", function()
    local selection = action_state.get_selected_entry()
    if selection then
      menus.show_copy_menu(selection.value)
    end
  end)
  
  -- Transition status with auto-refresh (in-place)
  local function transition_with_refresh()
    local selection = action_state.get_selected_entry()
    if not selection then return end
    
    local transitions = require("jira.transitions")
    local api = require("jira.api")
    local finders = require("telescope.finders")
    
    transitions.show_transition_picker(selection.value.key, function()
      -- On success: refresh picker in-place with refreshed data
      if jql then
        local response = api.search_issues(jql)
        if response and response.status == 200 then
          local data = vim.fn.json_decode(response.body)
          local issues = data.issues or {}
          api.cache.set_cached_issues(jql, issues)
          
          local picker = action_state.get_current_picker(prompt_bufnr)
          if picker then
            picker:refresh(finders.new_table({
              results = issues,
              entry_maker = function(entry)
                return {
                  value = entry,
                  display = format.format_issue_entry(entry),
                  ordinal = entry.key .. " " .. entry.fields.summary,
                }
              end,
            }), { reset_prompt = false })
          end
        end
      end
    end)
  end
  
  map("i", "<C-t>", transition_with_refresh)
  map("n", "<C-t>", transition_with_refresh)
  
  -- Assign to self
  map("i", "<C-a>", function()
    local selection = action_state.get_selected_entry()
    menus.assign_to_self(selection.value.key)
  end)
  
  map("n", "<C-a>", function()
    local selection = action_state.get_selected_entry()
    menus.assign_to_self(selection.value.key)
  end)
  
  -- Refresh issue data
  map("i", "<C-r>", function()
    local api = require("jira.api")
    api.cache.clear()
    vim.notify("Cache cleared. Rerun search to refresh.", vim.log.levels.INFO)
  end)
  
  map("n", "<C-r>", function()
    local api = require("jira.api")
    api.cache.clear()
    vim.notify("Cache cleared. Rerun search to refresh.", vim.log.levels.INFO)
  end)
  
  -- Open in browser
  map("i", "<C-o>", function()
    local selection = action_state.get_selected_entry()
    if selection then
      actions.close(prompt_bufnr)
      local url = config.jira_url .. "/browse/" .. selection.value.key
      utils.open_in_browser(url)
    end
  end)
  
  map("n", "<C-o>", function()
    local selection = action_state.get_selected_entry()
    if selection then
      actions.close(prompt_bufnr)
      local url = config.jira_url .. "/browse/" .. selection.value.key
      utils.open_in_browser(url)
    end
  end)
  
  -- Custom user-defined telescope mappings
  if config.telescope_mappings and type(config.telescope_mappings) == "table" then
    for key, handler in pairs(config.telescope_mappings) do
      if type(handler) == "function" then
        map("i", key, function()
          local selection = action_state.get_selected_entry()
          if selection then
            handler(selection.value, prompt_bufnr, actions)
          end
        end)
        
        map("n", key, function()
          local selection = action_state.get_selected_entry()
          if selection then
            handler(selection.value, prompt_bufnr, actions)
          end
        end)
      end
    end
  end
end

-- My Issues with status cycling
function M.my_issues_with_status_filter()
  -- Authentication happens lazily in api.make_request()
  -- No need to check state.authenticated here
  
  -- Lazy load telescope modules
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    vim.notify("Telescope not found. Please install telescope.nvim", vim.log.levels.ERROR)
    return
  end
  local api = require("jira.api")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")
  
  -- Status cycle list - use config or defaults
  local statuses = config.status_filters or {"To Do", "In Progress", "Done"}
  
  -- Find the index of the default status
  local default_status = config.default_status or "In Progress"
  local current_status_idx = 1  -- fallback to first status
  for i, status in ipairs(statuses) do
    if status == default_status then
      current_status_idx = i
      break
    end
  end
  
  local function get_current_status()
    return statuses[current_status_idx]
  end
  
  local function cycle_status()
    current_status_idx = current_status_idx + 1
    if current_status_idx > #statuses then
      current_status_idx = 1
    end
    return get_current_status()
  end
  
  local function cycle_status_backwards()
    current_status_idx = current_status_idx - 1
    if current_status_idx < 1 then
      current_status_idx = #statuses
    end
    return get_current_status()
  end
  
  local function fetch_issues(status)
    local jql = api.jql.my_issues_with_status(status)
    vim.notify("Fetching issues with status: " .. status, vim.log.levels.INFO)
    
    local response = api.search_issues(jql)
    if not response or response.status ~= 200 then
      vim.notify("Failed to fetch issues", vim.log.levels.ERROR)
      return {}
    end
    
    local data = vim.fn.json_decode(response.body)
    return data.issues or {}
  end
  
  local function create_picker(initial_issues)
    local current_picker
    
    current_picker = pickers.new({}, {
      prompt_title = "My Issues [Status: " .. get_current_status() .. "] - <C-s>/<C-b> to cycle",
      finder = finders.new_table({
        results = initial_issues,
        entry_maker = function(entry)
          return {
            value = entry,
            display = format.format_issue_entry(entry),
            ordinal = entry.key .. " " .. entry.fields.summary,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = M.create_issue_previewer(),
      attach_mappings = function(prompt_bufnr, map)
        -- Status cycling with Ctrl+s
        local function status_cycle_action()
          local new_status = cycle_status()
          local new_issues = fetch_issues(new_status)
          
          -- Close current picker and open new one with updated title
          actions.close(prompt_bufnr)
          
          -- Create new picker with updated status
          local new_picker = create_picker(new_issues)
          new_picker:find()
          
          vim.notify("Switched to status: " .. new_status .. " (" .. #new_issues .. " issues)", vim.log.levels.INFO)
        end
        
        -- Insert mode mapping with return true to prevent character insertion
        map("i", "<C-s>", function()
          status_cycle_action()
          return true
        end)
        map("n", "<C-s>", status_cycle_action)
        
        -- Status cycling backwards with Ctrl+b
        local function status_cycle_backwards_action()
          local new_status = cycle_status_backwards()
          local new_issues = fetch_issues(new_status)
          
          -- Close current picker and open new one with updated title
          actions.close(prompt_bufnr)
          
          -- Create new picker with updated status
          local new_picker = create_picker(new_issues)
          new_picker:find()
        end
        
        map("i", "<C-b>", function()
          status_cycle_backwards_action()
          return true
        end)
        map("n", "<C-b>", status_cycle_backwards_action)
        
        -- Default action: open in buffer
        local buffer = require("jira.ui.buffer")
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          buffer.open_issue_in_buffer(selection.value)
        end)
        
        -- Copy with format menu
        map("i", "<C-y>", function()
          local selection = action_state.get_selected_entry()
          if selection then
            menus.show_copy_menu(selection.value)
          end
        end)
        
        map("n", "<C-y>", function()
          local selection = action_state.get_selected_entry()
          if selection then
            menus.show_copy_menu(selection.value)
          end
        end)
        
        -- Transition status with auto-refresh (in-place)
        local function transition_with_refresh()
          local selection = action_state.get_selected_entry()
          if not selection then return end
          
          local transitions = require("jira.transitions")
          transitions.show_transition_picker(selection.value.key, function()
            -- On success: refresh picker in-place with same status filter
            local new_issues = fetch_issues(get_current_status())
            local picker = action_state.get_current_picker(prompt_bufnr)
            if picker then
              picker:refresh(finders.new_table({
                results = new_issues,
                entry_maker = function(entry)
                  return {
                    value = entry,
                    display = format.format_issue_entry(entry),
                    ordinal = entry.key .. " " .. entry.fields.summary,
                  }
                end,
              }), { reset_prompt = false })
            end
          end)
        end
        
        map("i", "<C-t>", transition_with_refresh)
        map("n", "<C-t>", transition_with_refresh)
        
        -- Assign to self
        map("i", "<C-a>", function()
          local selection = action_state.get_selected_entry()
          menus.assign_to_self(selection.value.key)
        end)
        
        map("n", "<C-a>", function()
          local selection = action_state.get_selected_entry()
          menus.assign_to_self(selection.value.key)
        end)
        
        -- Refresh issue data
        map("i", "<C-r>", function()
          api.cache.clear()
          local new_issues = fetch_issues(get_current_status())
          
          -- Close and recreate picker with refreshed data
          actions.close(prompt_bufnr)
          local new_picker = create_picker(new_issues)
          new_picker:find()
        end)
        
        map("n", "<C-r>", function()
          api.cache.clear()
          local new_issues = fetch_issues(get_current_status())
          
          -- Close and recreate picker with refreshed data
          actions.close(prompt_bufnr)
          local new_picker = create_picker(new_issues)
          new_picker:find()
        end)
        
        -- Open in browser
        map("i", "<C-o>", function()
          local selection = action_state.get_selected_entry()
          if selection then
            actions.close(prompt_bufnr)
            local url = config.jira_url .. "/browse/" .. selection.value.key
            utils.open_in_browser(url)
          end
        end)
        
        map("n", "<C-o>", function()
          local selection = action_state.get_selected_entry()
          if selection then
            actions.close(prompt_bufnr)
            local url = config.jira_url .. "/browse/" .. selection.value.key
            utils.open_in_browser(url)
          end
        end)
        
        -- Custom user-defined telescope mappings
        if config.telescope_mappings and type(config.telescope_mappings) == "table" then
          for key, handler in pairs(config.telescope_mappings) do
            if type(handler) == "function" then
              map("i", key, function()
                local selection = action_state.get_selected_entry()
                if selection then
                  handler(selection.value, prompt_bufnr, actions)
                end
              end)
              
              map("n", key, function()
                local selection = action_state.get_selected_entry()
                if selection then
                  handler(selection.value, prompt_bufnr, actions)
                end
              end)
            end
          end
        end
        
        return true
      end,
    })
    
    return current_picker
  end
  
  -- Fetch initial issues with default status
  local initial_issues = fetch_issues(get_current_status())
  local picker = create_picker(initial_issues)
  picker:find()
end

-- Open the most recently opened issue
function M.show_recent_issue()
  local recent = require("jira.recent")
  local recent_data = recent.get_recent()
  
  if not recent_data or not recent_data.key then
    vim.notify("No recent ticket found", vim.log.levels.INFO)
    return
  end
  
  local issue_key = recent_data.key
  vim.notify("Opening recent ticket: " .. issue_key, vim.log.levels.INFO)
  
  -- Open directly in buffer
  local buffer = require("jira.ui.buffer")
  buffer.open_issue_in_buffer({key = issue_key})
end

return M

