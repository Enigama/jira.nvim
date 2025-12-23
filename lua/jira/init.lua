local M = {}

-- Configuration
M.config = {
  jira_url = "https://your-company.atlassian.net",  -- Replace with your Jira URL
  auth_token = nil,
  auth_header = nil,
  jira_email = nil,
  cache_dir = vim.fn.stdpath("cache") .. "/jira",
  default_project = nil,
  max_results = 50,
  auto_refresh_interval = 300, -- 5 minutes
  -- Status filter configuration for "My Issues" picker
  -- Users can customize these to match their Jira workflow
  -- Example: {"Backlog", "Ready for Dev", "In Progress", "In Review", "Merged", "Ready for QA", "All"}
  status_filters = {"To Do", "In Progress", "Done"},
  default_status = "In Progress",
  -- Custom telescope mappings - users can add custom keybindings and handlers
  -- Example: telescope_mappings = { ["<C-g>"] = function(issue, prompt_bufnr, actions) ... end }
  telescope_mappings = {},
}

-- State
M.state = {
  authenticated = false,
  current_user = nil,
  cached_issues = {},
  pending_command = nil,
  auth_in_progress = false,
}

-- Modules
local auth = require("jira.auth")
local api = require("jira.api")
local ui = require("jira.ui")
local transitions = require("jira.transitions")
local comments = require("jira.comments")

function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)
  
  -- Create cache directory
  vim.fn.mkdir(M.config.cache_dir, "p")
  
  -- Initialize modules
  auth.setup(M.config)
  api.setup(M.config)
  ui.setup(M.config)
  transitions.setup(M.config)
  comments.setup(M.config)
  
  -- Setup commands
  M.setup_commands()
  
  -- Note: Authentication now happens lazily on first API call (octo.nvim style)
  -- No need to auto-authenticate in setup
end

function M.setup_commands()
  -- Main search command
  vim.api.nvim_create_user_command("JiraSearch", function()
    M.search()
  end, { desc = "Search Jira issues" })
  
  -- Direct issue lookup
  vim.api.nvim_create_user_command("JiraIssue", function(opts)
    M.get_issue(opts.args)
  end, { desc = "Get Jira issue by key", nargs = 1 })
  
  -- My issues
  vim.api.nvim_create_user_command("JiraMyIssues", function()
    M.my_issues()
  end, { desc = "Show issues assigned to me" })
  
  -- Recent issue
  vim.api.nvim_create_user_command("JiraRecent", function()
    M.open_recent()
  end, { desc = "Open most recently viewed issue" })
  
  -- Project issues
  vim.api.nvim_create_user_command("JiraProject", function(opts)
    M.project_issues(opts.args)
  end, { desc = "Show issues for a project", nargs = 1 })
  
  -- Authentication
  vim.api.nvim_create_user_command("JiraAuth", function()
    M.authenticate()
  end, { desc = "Authenticate with Jira" })
  
  -- Logout
  vim.api.nvim_create_user_command("JiraLogout", function()
    M.logout()
  end, { desc = "Logout from Jira" })
  
  -- Projects list
  vim.api.nvim_create_user_command("JiraProjects", function()
    M.list_projects()
  end, { desc = "List all Jira projects" })
  
  -- Clear cache
  vim.api.nvim_create_user_command("JiraClearCache", function()
    M.clear_cache()
  end, { desc = "Clear Jira cache" })
  
  -- Test authentication (for debugging)
  vim.api.nvim_create_user_command("JiraTestAuth", function()
    M.test_auth()
  end, { desc = "Test Jira authentication" })
  
  -- Show authentication status
  vim.api.nvim_create_user_command("JiraStatus", function()
    M.show_auth_status()
  end, { desc = "Show Jira authentication status" })
end

-- Manual authentication (for explicit re-auth)
function M.authenticate()
  auth.authenticate()
end

-- Commands no longer need auth checks - authentication happens lazily in api.make_request()
function M.search()
  ui.search_issues()
end

function M.get_issue(issue_key)
  if not issue_key or issue_key == "" then
    vim.notify("Please provide an issue key", vim.log.levels.WARN)
    return
  end
  
  vim.notify("Fetching issue " .. issue_key .. "...", vim.log.levels.INFO)
  
  local response = api.get_issue(issue_key)
  
  if not response or response.status ~= 200 then
    vim.notify("Failed to fetch issue " .. issue_key, vim.log.levels.ERROR)
    return
  end
  
  local issue = vim.fn.json_decode(response.body)
  ui.show_telescope_picker({issue}, "key = " .. issue_key)
end

function M.my_issues()
  -- Use the new status filter function with cycling
  ui.my_issues_with_status_filter()
end

function M.open_recent()
  ui.show_recent_issue()
end

function M.project_issues(project_key)
  if not project_key or project_key == "" then
    vim.notify("Please provide a project key", vim.log.levels.WARN)
    return
  end
  
  vim.notify("Fetching issues for project " .. project_key .. "...", vim.log.levels.INFO)
  
  local jql = api.jql.by_project(project_key)
  local response = api.search_issues(jql)
  
  if not response or response.status ~= 200 then
    vim.notify("Failed to fetch project issues", vim.log.levels.ERROR)
    return
  end
  
  local data = vim.fn.json_decode(response.body)
  local issues = data.issues or {}
  
  api.cache.set_cached_issues(jql, issues)
  ui.show_telescope_picker(issues, jql)
end

function M.list_projects()
  vim.notify("Fetching projects...", vim.log.levels.INFO)
  
  local response = api.get_projects()
  
  if not response or response.status ~= 200 then
    vim.notify("Failed to fetch projects", vim.log.levels.ERROR)
    return
  end
  
  local projects = vim.fn.json_decode(response.body)
  
  if not projects or #projects == 0 then
    vim.notify("No projects found", vim.log.levels.INFO)
    return
  end
  
  local project_names = {}
  local project_map = {}
  
  for _, project in ipairs(projects) do
    local display = string.format("[%s] %s", project.key, project.name)
    table.insert(project_names, display)
    project_map[display] = project.key
  end
  
  vim.ui.select(project_names, {
    prompt = "Select a project:",
  }, function(choice)
    if choice then
      local project_key = project_map[choice]
      M.project_issues(project_key)
    end
  end)
end

-- Show current authentication status
function M.show_auth_status()
  local status = auth.get_auth_status()
  
  if status.authenticated then
    local user = status.user
    local lines = {
      "✅ Authenticated with Jira",
      "",
      "User: " .. (user.displayName or user.name or "Unknown"),
      "Email: " .. (status.email or user.emailAddress or "Unknown"),
      "Account ID: " .. (user.accountId or "Unknown"),
      "",
      "Cache: vim.g.jira_auth_header (session-persistent)",
    }
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  else
    vim.notify("❌ Not authenticated. Run any Jira command to authenticate automatically.", vim.log.levels.WARN)
  end
end

function M.logout()
  auth.logout()
  M.state.pending_command = nil
  M.state.auth_in_progress = false
end

function M.clear_cache()
  api.cache.clear()
  vim.notify("Jira cache cleared", vim.log.levels.INFO)
end

function M.test_auth()
  local token = vim.fn.getenv("JIRA_TOKEN")
  if token == vim.NIL or token == "" then
    vim.notify("❌ JIRA_TOKEN not found in environment", vim.log.levels.ERROR)
    return
  end
  
  local email = auth.get_jira_email()
  if not email then
    vim.notify("❌ Jira email not cached. Please run :JiraAuth first", vim.log.levels.ERROR)
    return
  end
  
  if not M.config.auth_header then
    vim.notify("❌ Auth header not configured", vim.log.levels.ERROR)
    return
  end
  
  local response = api.get_current_user()
  
  if response then
    if response.status == 200 then
      vim.notify("✅ Authentication successful!", vim.log.levels.INFO)
    else
      vim.notify("❌ Authentication failed", vim.log.levels.ERROR)
      if response.body then
        vim.notify("Error: " .. response.body, vim.log.levels.ERROR)
      end
    end
  else
    vim.notify("❌ No response from API", vim.log.levels.ERROR)
  end
end

-- Export modules for external use
M.auth = auth
M.api = api
M.ui = ui
M.transitions = transitions
M.comments = comments

return M

