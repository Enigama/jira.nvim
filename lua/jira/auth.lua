local M = {}

local config = nil

function M.setup(cfg)
  config = cfg
end

-- Get state dynamically to avoid stale references
local function get_state()
  return require("jira").state
end

-- Base64 encoding function
local function base64_encode(data)
  local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  return ((data:gsub('.', function(x)
    local r, b = '', x:byte()
    for i = 8, 1, -1 do
      r = r .. (b % 2^i - b % 2^(i-1) > 0 and '1' or '0')
    end
    return r
  end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
    if (#x < 6) then return '' end
    local c = 0
    for i = 1, 6 do
      c = c + (x:sub(i, i) == '1' and 2^(6-i) or 0)
    end
    return b:sub(c+1, c+1)
  end)..({ '', '==', '=' })[#data % 3 + 1])
end

-- Get JIRA_TOKEN from environment
function M.get_token_from_env()
  local token = vim.fn.getenv("JIRA_TOKEN")
  if token == vim.NIL or token == "" then
    return nil
  end
  return token
end

-- Get or prompt for Jira email
function M.get_jira_email()
  -- Check if email is cached
  local cache_file = config.cache_dir .. "/jira_email"
  local file = io.open(cache_file, "r")
  if file then
    local email = file:read("*a")
    file:close()
    return vim.trim(email)
  end
  
  -- Prompt for email
  return nil
end

-- Save Jira email to cache
function M.save_jira_email(email)
  local cache_file = config.cache_dir .. "/jira_email"
  local file = io.open(cache_file, "w")
  if file then
    file:write(email)
    file:close()
    return true
  end
  return false
end

-- Validate the token by making a test API call
function M.validate_token()
  if not config.auth_header then
    return false
  end
  
  -- Test credentials by calling the /myself endpoint
  local api = require("jira.api")
  local response = api.get_current_user()
  
  if response and response.status == 200 then
    return true
  end
  
  return false
end

-- Authenticate and validate
function M.authenticate()
  local jira = require("jira")
  jira.state.auth_in_progress = true
  
  local token = M.get_token_from_env()
  
  if not token then
    jira.state.auth_in_progress = false
    vim.notify(
      "JIRA_TOKEN environment variable not found. Please set it in your shell configuration.",
      vim.log.levels.ERROR
    )
    return false
  end
  
  vim.notify("🔐 Authenticating with Jira...", vim.log.levels.INFO)
  
  -- Get email (from cache or prompt)
  local email = M.get_jira_email()
  
  if not email then
    vim.ui.input({
      prompt = "Enter your Jira email address: ",
      default = "",
    }, function(input)
      if input and input ~= "" then
        M.save_jira_email(input)
        M.complete_authentication(input, token)
      else
        vim.notify("Email is required for Jira authentication", vim.log.levels.ERROR)
      end
    end)
    return
  end
  
  M.complete_authentication(email, token)
end

-- Build auth header from email and token
function M.build_auth_header(email, token)
  local credentials = email .. ":" .. token
  return "Basic " .. base64_encode(credentials)
end

-- Synchronous validation and user info retrieval
function M.validate_and_get_user_sync(auth_header)
  -- Make synchronous API call using curl directly
  local url = config.jira_url .. "/rest/api/3/myself"
  local cmd = {
    "curl", "-s", "-w", "\n%{http_code}",
    "-H", "Authorization: " .. auth_header,
    "-H", "Content-Type: application/json",
    "-H", "Accept: application/json",
    "--connect-timeout", "10",
    "--max-time", "30",
    url
  }
  
  local result = vim.fn.system(cmd)
  
  -- Parse response
  local lines = vim.split(result, "\n")
  local status = tonumber(lines[#lines])
  
  if status == 200 then
    table.remove(lines)
    local body = table.concat(lines, "")
    return vim.fn.json_decode(body)
  end
  
  return nil
end

-- Synchronous email prompt (blocks until user responds)
function M.prompt_email_sync()
  local email = nil
  local done = false
  
  vim.ui.input({
    prompt = "Enter your Jira email address: ",
    default = "",
  }, function(input)
    email = input
    done = true
  end)
  
  -- Wait for input (with 30 second timeout)
  vim.wait(30000, function() return done end, 100)
  
  return email and email ~= "" and email or nil
end

-- Clear email cache
function M.clear_email_cache()
  local cache_file = config.cache_dir .. "/jira_email"
  vim.fn.delete(cache_file)
end

-- Save auth cache to disk with timestamp
function M.save_auth_cache(auth_header, email, user_data)
  local cache_file = config.cache_dir .. "/auth_cache.json"
  local cache_data = {
    auth_header = auth_header,
    email = email,
    user = user_data,
    validated_at = os.time()
  }
  
  -- Ensure directory exists
  vim.fn.mkdir(config.cache_dir, "p")
  
  local file, err = io.open(cache_file, "w")
  if not file then
    vim.notify("Failed to save auth cache: " .. (err or "unknown error"), vim.log.levels.WARN)
    return false
  end
  
  local json_str = vim.fn.json_encode(cache_data)
  file:write(json_str)
  file:close()
  
  -- Verify file was written
  local verify = io.open(cache_file, "r")
  if verify then
    verify:close()
    return true
  end
  
  return false
end

-- Load auth cache from disk
-- Returns cached data if fresh (< 24 hours old), nil otherwise
function M.load_auth_cache()
  if not config or not config.cache_dir then
    return nil
  end
  
  local cache_file = config.cache_dir .. "/auth_cache.json"
  local file = io.open(cache_file, "r")
  
  if not file then
    return nil
  end
  
  local content = file:read("*a")
  file:close()
  
  if not content or content == "" then
    return nil
  end
  
  local ok, cache_data = pcall(vim.fn.json_decode, content)
  if not ok or not cache_data then
    return nil
  end
  
  -- Check if cache is fresh (< 24 hours old)
  local cache_age = os.time() - (cache_data.validated_at or 0)
  local max_age = 24 * 60 * 60 -- 24 hours in seconds
  
  if cache_age < max_age then
    return cache_data
  end
  
  return nil
end

-- Clear auth cache
function M.clear_auth_cache()
  local cache_file = config.cache_dir .. "/auth_cache.json"
  vim.fn.delete(cache_file)
end

-- Synchronous authentication - called automatically on first API call
-- This is the main function that implements the lazy auth pattern like octo.nvim
-- Now with persistent disk cache - only validates when cache is stale or missing
function M.ensure_authenticated(force_reauth)
  force_reauth = force_reauth or false
  
  -- 1. Check if already authenticated in current session (vim.g)
  if not force_reauth and vim.g.jira_auth_header and vim.g.jira_viewer then
    -- Update config with cached values
    config.auth_header = vim.g.jira_auth_header
    config.jira_email = vim.g.jira_email
    return true
  end
  
  -- 2. Try to load from persistent disk cache (< 24h old)
  if not force_reauth then
    local cached = M.load_auth_cache()
    if cached and cached.auth_header and cached.user then
      -- Use cached credentials without validation
      vim.g.jira_auth_header = cached.auth_header
      vim.g.jira_email = cached.email
      vim.g.jira_viewer = cached.user
      
      config.auth_header = cached.auth_header
      config.jira_email = cached.email
      
      -- Silent - no notification for cached auth
      return true
    end
  end
  
  -- 3. No valid cache - need to authenticate
  -- Get token (fail fast if missing)
  local token = M.get_token_from_env()
  if not token then
    vim.notify("JIRA_TOKEN not found. Please set it in your environment.", vim.log.levels.ERROR)
    return false
  end
  
  -- 4. Get email (from disk cache or prompt synchronously)
  local email = M.get_jira_email()
  if not email then
    email = M.prompt_email_sync()
    if not email then
      vim.notify("Email is required for Jira authentication", vim.log.levels.ERROR)
      return false
    end
  end
  
  vim.notify("🔐 Authenticating with Jira...", vim.log.levels.INFO)
  
  -- 5. Build auth header
  local auth_header = M.build_auth_header(email, token)
  
  -- 6. Validate with synchronous API call
  local user_data = M.validate_and_get_user_sync(auth_header)
  if not user_data then
    vim.notify(
      "Failed to authenticate with Jira. Please check your email and JIRA_TOKEN.",
      vim.log.levels.ERROR
    )
    M.clear_email_cache()
    M.clear_auth_cache()
    return false
  end
  
  -- 7. Cache everything in vim.g (session-persistent)
  vim.g.jira_auth_header = auth_header
  vim.g.jira_email = email
  vim.g.jira_viewer = user_data
  
  -- 8. Update config
  config.auth_header = auth_header
  config.jira_email = email
  config.auth_token = token
  
  -- 9. Save email to disk cache (for convenience)
  M.save_jira_email(email)
  
  -- 10. Save auth cache to disk (expires in 24h)
  M.save_auth_cache(auth_header, email, user_data)
  
  vim.notify("✅ Authenticated as " .. (user_data.displayName or user_data.emailAddress), vim.log.levels.INFO)
  return true
end

-- Handle authentication failure from API (401 error)
-- Re-authenticates and returns true if successful
function M.handle_auth_failure()
  -- Clear all caches
  vim.g.jira_auth_header = nil
  vim.g.jira_email = nil
  vim.g.jira_viewer = nil
  M.clear_auth_cache()
  
  -- Try to re-authenticate
  vim.notify("Session expired. Re-authenticating...", vim.log.levels.WARN)
  return M.ensure_authenticated(true)
end

-- Complete authentication with email and token (kept for backward compatibility)
function M.complete_authentication(email, token)
  vim.notify("Validating Jira credentials...", vim.log.levels.INFO)
  
  -- Create Basic auth header: base64(email:token)
  local auth_header = M.build_auth_header(email, token)
  
  -- Validate the credentials
  local state = get_state()
  local jira = require("jira")
  
  local user_data = M.validate_and_get_user_sync(auth_header)
  if user_data then
    -- Cache in vim.g
    vim.g.jira_auth_header = auth_header
    vim.g.jira_email = email
    vim.g.jira_viewer = user_data
    
    -- Update config
    config.auth_header = auth_header
    config.jira_email = email
    config.auth_token = token
    
    state.authenticated = true
    state.auth_in_progress = false
    state.current_user = user_data
    
    -- Save email to disk cache
    M.save_jira_email(email)
    
    -- Save auth cache to disk (persistent across sessions)
    M.save_auth_cache(auth_header, email, user_data)
    
    vim.notify("✅ Successfully authenticated with Jira", vim.log.levels.INFO)
    vim.notify("Welcome, " .. (user_data.displayName or user_data.name or "User"), vim.log.levels.INFO)
    
    -- Execute pending command if exists
    if jira.state.pending_command then
      vim.notify("⚡ Executing queued command...", vim.log.levels.INFO)
      vim.schedule(function()
        jira.state.pending_command()
        jira.state.pending_command = nil
      end)
    end
    
    return true
  else
    state.auth_in_progress = false
    jira.state.pending_command = nil
    vim.notify(
      "Failed to authenticate with Jira. Please check your email and JIRA_TOKEN.",
      vim.log.levels.ERROR
    )
    state.authenticated = false
    M.clear_email_cache()
    M.clear_auth_cache()
    return false
  end
end

-- Get current user information
function M.get_user_info()
  local api = require("jira.api")
  local response = api.get_current_user()
  
  if response and response.status == 200 then
    local user_data = vim.fn.json_decode(response.body)
    local state = get_state()
    state.current_user = user_data
    vim.notify(
      "Welcome, " .. (user_data.displayName or user_data.name or "User"),
      vim.log.levels.INFO
    )
    return user_data
  end
  
  return nil
end

-- Check if authenticated
function M.is_authenticated()
  local state = get_state()
  return state.authenticated
end

-- Logout
function M.logout()
  local state = get_state()
  local jira = require("jira")
  
  state.authenticated = false
  state.current_user = nil
  state.auth_in_progress = false
  jira.state.pending_command = nil
  
  config.auth_token = nil
  config.auth_header = nil
  config.jira_email = nil
  
  -- Clear vim.g cache
  vim.g.jira_auth_header = nil
  vim.g.jira_email = nil
  vim.g.jira_viewer = nil
  
  -- Clear disk caches
  M.clear_email_cache()
  M.clear_auth_cache()
  
  vim.notify("Logged out from Jira (cleared all caches)", vim.log.levels.INFO)
end

-- Get current authentication status
function M.get_auth_status()
  if vim.g.jira_viewer then
    return {
      authenticated = true,
      user = vim.g.jira_viewer,
      email = vim.g.jira_email
    }
  end
  return {
    authenticated = false
  }
end

return M

