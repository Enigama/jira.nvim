local M = {}

local config = nil
local utils = require("jira.ui.utils")
local format = require("jira.ui.format")
local menus = require("jira.ui.menus")
local recent = require("jira.recent")

function M.setup(cfg)
  config = cfg
  recent.setup(cfg)
end

-- Open issue in a buffer with markdown formatting
function M.open_issue_in_buffer(issue)
  local issue_key = issue.key
  if not issue_key then
    vim.notify("Issue key not found", vim.log.levels.ERROR)
    return
  end
  
  local api = require("jira.api")
  
  -- Check if buffer already exists and has content
  local buf_name = "jira://" .. issue_key
  local existing_buf = vim.fn.bufnr(buf_name)
  if existing_buf ~= -1 then
    -- Verify buffer has content
    local line_count = vim.api.nvim_buf_line_count(existing_buf)
    local first_line = ""
    if line_count > 0 then
      local lines = vim.api.nvim_buf_get_lines(existing_buf, 0, 1, false)
      first_line = lines[1] or ""
    end
    
    -- If buffer is empty or only has error message, recreate it
    if line_count <= 1 or first_line:match("^# Error") or first_line:match("^# Warning") or first_line == "" then
      -- Delete the bad buffer
      pcall(vim.api.nvim_buf_delete, existing_buf, { force = true })
      -- Clear cache to force refresh
      api.cache.clear_cached_issue(issue_key)
    else
      -- Buffer exists with content, reuse it
      vim.cmd("tab split")
      vim.api.nvim_set_current_buf(existing_buf)
      return
    end
  end
  
  -- Try to get full issue details from cache
  local full_issue = api.cache.get_cached_issue(issue_key)
  
  if not full_issue then
    -- Fetch full issue details
    local response = api.get_issue(issue_key)
    if response and response.status == 200 then
      local decode_ok, decoded = pcall(vim.fn.json_decode, response.body)
      if decode_ok and decoded then
        full_issue = decoded
        api.cache.set_cached_issue(issue_key, full_issue)
      else
        vim.notify("Failed to decode issue JSON for " .. issue_key, vim.log.levels.ERROR)
        return
      end
    else
      local status = response and response.status or "no response"
      vim.notify("Failed to load issue details (status: " .. tostring(status) .. ")", vim.log.levels.ERROR)
      return
    end
  end
  
  -- Validate we have the required data
  if not full_issue or not full_issue.fields then
    vim.notify("Issue data incomplete for " .. issue_key, vim.log.levels.ERROR)
    api.cache.clear_cached_issue(issue_key)
    return
  end
  
  -- Create new buffer ONLY after we have valid content
  local bufnr = vim.api.nvim_create_buf(false, true)
  if bufnr == 0 then
    vim.notify("Failed to create buffer", vim.log.levels.ERROR)
    return
  end
  
  -- Format content with error handling
  local success, markdown_lines = pcall(format.format_issue_as_markdown, full_issue)
  
  if not success then
    vim.notify("Error formatting issue: " .. tostring(markdown_lines), vim.log.levels.ERROR)
    -- Clean up buffer
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    return
  end
  
  if not markdown_lines or #markdown_lines == 0 then
    vim.notify("Warning: Issue formatted with no content for " .. issue_key, vim.log.levels.WARN)
    -- Clean up buffer
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    return
  end
  
  -- Set buffer content BEFORE naming/displaying it
  local lines_set_success, err = pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, markdown_lines)
  
  if not lines_set_success then
    vim.notify("Failed to set buffer lines: " .. tostring(err), vim.log.levels.ERROR)
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    return
  end
  
  -- Verify content was actually set
  local verify_count = vim.api.nvim_buf_line_count(bufnr)
  if verify_count < 5 then  -- Should have at least title, metadata, etc.
    vim.notify("Buffer content verification failed (only " .. verify_count .. " lines)", vim.log.levels.ERROR)
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    return
  end
  
  -- NOW set buffer options
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].readonly = true
  vim.bo[bufnr].modifiable = false
  
  -- Set buffer name AFTER we know content is good
  pcall(vim.api.nvim_buf_set_name, bufnr, buf_name)
  
  -- Switch to the buffer in a new tab
  vim.cmd("tab split")
  vim.api.nvim_set_current_buf(bufnr)
  
  -- Set up buffer-local keymaps
  M.setup_buffer_keymaps(bufnr, issue_key, full_issue)
  
  -- Save as most recently opened ticket
  recent.save_recent(issue_key)
  
  -- Success! Final verification
  local final_line_count = vim.api.nvim_buf_line_count(bufnr)
end

-- Set up buffer-local keymaps
function M.setup_buffer_keymaps(bufnr, issue_key, full_issue)
  local opts = { noremap = true, silent = true, buffer = bufnr }
  
  -- Close buffer
  vim.keymap.set("n", "q", function()
    vim.cmd("bdelete")
  end, vim.tbl_extend("force", opts, { desc = "Close buffer" }))
  
  -- Open in browser
  vim.keymap.set("n", "<C-o>", function()
    local url = config.jira_url .. "/browse/" .. issue_key
    utils.open_in_browser(url)
  end, vim.tbl_extend("force", opts, { desc = "Open in browser" }))
  
  vim.keymap.set("n", "o", function()
    local url = config.jira_url .. "/browse/" .. issue_key
    utils.open_in_browser(url)
  end, vim.tbl_extend("force", opts, { desc = "Open in browser" }))
  
  -- Copy menu
  vim.keymap.set("n", "<C-y>", function()
    menus.show_copy_menu(full_issue)
  end, vim.tbl_extend("force", opts, { desc = "Copy issue info" }))
  
  -- Transition status
  vim.keymap.set("n", "<C-t>", function()
    local transitions = require("jira.transitions")
    transitions.show_transition_picker(issue_key)
  end, vim.tbl_extend("force", opts, { desc = "Transition issue" }))
  
  -- Assign to self
  vim.keymap.set("n", "<C-a>", function()
    local state = utils.get_state()
    if not state.current_user or not state.current_user.accountId then
      vim.notify("Current user information not available", vim.log.levels.ERROR)
      return
    end
    
    local api = require("jira.api")
    local response = api.assign_issue(issue_key, state.current_user.accountId)
    
    if response and response.status == 204 then
      vim.notify("Successfully assigned " .. issue_key .. " to you", vim.log.levels.INFO)
      api.cache.clear()
      -- Refresh buffer
      vim.cmd("bdelete")
      vim.defer_fn(function()
        M.open_issue_in_buffer({key = issue_key})
      end, 100)
    else
      vim.notify("Failed to assign " .. issue_key, vim.log.levels.ERROR)
    end
  end, vim.tbl_extend("force", opts, { desc = "Assign to self" }))
  
  -- Refresh buffer
  vim.keymap.set("n", "<C-r>", function()
    vim.cmd("bdelete")
    vim.defer_fn(function()
      M.open_issue_in_buffer({key = issue_key})
    end, 100)
  end, vim.tbl_extend("force", opts, { desc = "Refresh buffer" }))
  
  -- Add comment
  vim.keymap.set("n", "<C-c>", function()
    local comments = require("jira.comments")
    comments.open_comment_window(issue_key)
  end, vim.tbl_extend("force", opts, { desc = "Add comment" }))
end

return M

