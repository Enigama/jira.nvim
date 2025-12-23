local M = {}

local config = nil

function M.setup(cfg)
  config = cfg
end

-- Make HTTP request using curl
function M.make_request(endpoint, method, body, extra_headers, _retry_count)
  method = method or "GET"
  _retry_count = _retry_count or 0
  
  -- Lazy authenticate on first API call (synchronous, octo.nvim style)
  if not vim.g.jira_auth_header then
    local auth = require("jira.auth")
    local success = auth.ensure_authenticated()
    if not success then
      return { status = 401, body = '{"error": "Authentication failed"}' }
    end
  end
  
  local url = config.jira_url .. endpoint
  
  local curl_cmd = {
    "curl",
    "-s",
    "-w", "\n%{http_code}",
    "-X", method,
    "-H", "Content-Type: application/json",
    "-H", "Accept: application/json",
    "--connect-timeout", "10",
    "--max-time", "30",
  }
  
  -- Add authorization header from cache
  if vim.g.jira_auth_header then
    table.insert(curl_cmd, "-H")
    table.insert(curl_cmd, "Authorization: " .. vim.g.jira_auth_header)
  end
  
  -- Add extra headers if provided
  if extra_headers then
    for key, value in pairs(extra_headers) do
      table.insert(curl_cmd, "-H")
      table.insert(curl_cmd, key .. ": " .. value)
    end
  end
  
  -- Add body if provided
  if body then
    table.insert(curl_cmd, "-d")
    table.insert(curl_cmd, vim.fn.json_encode(body))
  end
  
  -- Add URL
  table.insert(curl_cmd, url)
  
  local output = {}
  local stderr_output = {}
  
  local job_id = vim.fn.jobstart(curl_cmd, {
    on_stdout = function(_, data, _)
      for _, line in ipairs(data) do
        table.insert(output, line)
      end
    end,
    on_stderr = function(_, data, _)
      for _, line in ipairs(data) do
        table.insert(stderr_output, line)
      end
    end,
  })
  
  if job_id == 0 then
    vim.notify("Failed to start curl job", vim.log.levels.ERROR)
    return nil
  end
  
  local result = vim.fn.jobwait({job_id}, 30000)[1]
  
  if result ~= 0 then
    if #stderr_output > 0 then
      vim.notify("API request failed: " .. table.concat(stderr_output, "\n"), vim.log.levels.ERROR)
    end
    return nil
  end
  
  if not output or #output == 0 then
    return nil
  end
  
  -- Find the HTTP status code - it should be the last non-empty line
  local status_code = nil
  local response_body_lines = {}
  
  for i = #output, 1, -1 do
    local line = output[i]
    if line and line ~= "" then
      status_code = tonumber(line)
      if status_code then
        response_body_lines = vim.list_slice(output, 1, i - 1)
        break
      end
    end
  end
  
  -- Join without newlines to avoid JSON parsing issues
  local response_body = table.concat(response_body_lines, "")
  
  local response = {
    status = status_code,
    body = response_body
  }
  
  -- Handle 401 Unauthorized - credentials expired or invalid
  if status_code == 401 and _retry_count == 0 then
    local auth = require("jira.auth")
    local reauth_success = auth.handle_auth_failure()
    
    if reauth_success then
      -- Retry the request once with new credentials
      return M.make_request(endpoint, method, body, extra_headers, 1)
    end
  end
  
  return response
end

-- Get current user
function M.get_current_user()
  return M.make_request("/rest/api/3/myself", "GET")
end

-- URL encode function
local function url_encode(str)
  if str then
    str = string.gsub(str, "\n", "\r\n")
    str = string.gsub(str, "([^%w %-%_%.%~])",
      function(c) return string.format("%%%02X", string.byte(c)) end)
    str = string.gsub(str, " ", "+")
  end
  return str
end

-- Search issues using JQL (new endpoint)
function M.search_issues(jql, start_at, max_results)
  start_at = start_at or 0
  max_results = max_results or config.max_results or 50
  
  -- Use the new /search/jql endpoint as per Jira API deprecation notice
  local endpoint = string.format(
    "/rest/api/3/search/jql?jql=%s&startAt=%d&maxResults=%d&fields=*all",
    url_encode(jql),
    start_at,
    max_results
  )
  
  return M.make_request(endpoint, "GET")
end

-- Get single issue by key
function M.get_issue(issue_key)
  local endpoint = "/rest/api/3/issue/" .. issue_key .. "?fields=*all"
  return M.make_request(endpoint, "GET")
end

-- Get available transitions for an issue
function M.get_transitions(issue_key)
  local endpoint = "/rest/api/3/issue/" .. issue_key .. "/transitions?expand=transitions.fields"
  return M.make_request(endpoint, "GET")
end

-- Execute a transition
function M.do_transition(issue_key, transition_id, comment, fields)
  local endpoint = "/rest/api/3/issue/" .. issue_key .. "/transitions"
  
  local body = {
    transition = {
      id = transition_id
    }
  }
  
  -- Add custom fields if provided
  if fields then
    body.fields = fields
  end
  
  -- Add comment if provided
  if comment and comment ~= "" then
    body.update = {
      comment = {
        {
          add = {
            body = {
              type = "doc",
              version = 1,
              content = {
                {
                  type = "paragraph",
                  content = {
                    {
                      type = "text",
                      text = comment
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  end
  
  return M.make_request(endpoint, "POST", body)
end

-- Assign issue to user
function M.assign_issue(issue_key, account_id)
  local endpoint = "/rest/api/3/issue/" .. issue_key .. "/assignee"
  local body = {
    accountId = account_id
  }
  return M.make_request(endpoint, "PUT", body)
end

-- Add comment to issue
function M.add_comment(issue_key, comment_adf)
  local endpoint = "/rest/api/3/issue/" .. issue_key .. "/comment"
  local body = {
    body = comment_adf
  }
  return M.make_request(endpoint, "POST", body)
end

-- Get all projects
function M.get_projects()
  return M.make_request("/rest/api/3/project", "GET")
end

-- Search for users by name/email
function M.search_users(query)
  local endpoint = "/rest/api/3/user/search?query=" .. url_encode(query)
  return M.make_request(endpoint, "GET")
end

-- JQL Query Builder
M.jql = {}

function M.jql.all_issues(limit)
  return "ORDER BY updated DESC"
end

function M.jql.by_key(key)
  return string.format("key = %s", key)
end

function M.jql.by_assignee(assignee)
  if assignee == "currentUser()" then
    return "assignee = currentUser() ORDER BY updated DESC"
  end
  -- Escape quotes in assignee name and wrap in quotes for JQL
  local escaped = assignee:gsub('"', '\\"')
  return string.format('assignee = "%s" ORDER BY updated DESC', escaped)
end

function M.jql.by_account_id(account_id)
  return string.format('assignee = "%s" ORDER BY updated DESC', account_id)
end

function M.jql.by_text(text)
  -- Escape quotes and wrap in quotes for JQL text search
  local escaped = text:gsub('"', '\\"')
  return string.format('text ~ "%s" ORDER BY updated DESC', escaped)
end

function M.jql.by_project(project_key)
  return string.format("project = %s ORDER BY updated DESC", project_key)
end

function M.jql.my_issues()
  return "assignee = currentUser() ORDER BY updated DESC"
end

function M.jql.my_issues_with_status(status)
  if not status or status == "All" then
    return "assignee = currentUser() ORDER BY updated DESC"
  end
  local escaped = status:gsub('"', '\\"')
  return string.format('assignee = currentUser() AND status = "%s" ORDER BY updated DESC', escaped)
end

-- Cache management
M.cache = {
  issues = {},
  issue_details = {},
  last_search = nil,
  last_search_time = 0,
}

function M.cache.clear()
  M.cache.issues = {}
  M.cache.issue_details = {}
  M.cache.last_search = nil
  M.cache.last_search_time = 0
end

function M.cache.get_cached_issues(jql)
  local current_time = os.time()
  if M.cache.last_search == jql and 
     (current_time - M.cache.last_search_time) < (config.auto_refresh_interval or 300) then
    return M.cache.issues
  end
  return nil
end

function M.cache.set_cached_issues(jql, issues)
  M.cache.last_search = jql
  M.cache.last_search_time = os.time()
  M.cache.issues = issues
end

function M.cache.get_cached_issue(issue_key)
  local cache_entry = M.cache.issue_details[issue_key]
  if cache_entry then
    local current_time = os.time()
    if (current_time - cache_entry.timestamp) < 120 then -- 2 minutes
      return cache_entry.data
    end
  end
  return nil
end

function M.cache.set_cached_issue(issue_key, issue_data)
  M.cache.issue_details[issue_key] = {
    data = issue_data,
    timestamp = os.time()
  }
end

function M.cache.clear_cached_issue(issue_key)
  M.cache.issue_details[issue_key] = nil
end

return M

