local M = {}

local config = nil
local api = nil

function M.setup(cfg)
  config = cfg
  api = require("jira.api")
end

-- Parse text and extract mentions in format @[Display Name](accountId)
local function parse_mentions(text)
  local mentions = {}
  for display_name, account_id in text:gmatch("@%[([^%]]+)%]%(([^%)]+)%)") do
    mentions[display_name] = account_id
  end
  return mentions
end

-- Convert text with mentions to ADF format
local function text_to_adf(text, mentions_map)
  -- Create ADF document structure
  local adf = {
    type = "doc",
    version = 1,
    content = {}
  }
  
  -- Split text into lines
  local lines = vim.split(text, "\n", { plain = true })
  
  for _, line in ipairs(lines) do
    local paragraph = {
      type = "paragraph",
      content = {}
    }
    
    -- Parse line for mentions and regular text
    local last_pos = 1
    local line_content = {}
    
    -- Find all mentions in the line
    for display_name, account_id in line:gmatch("@%[([^%]]+)%]%(([^%)]+)%)") do
      local mention_pattern = "@%[" .. display_name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "%]%(" .. account_id:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "%)"
      local start_pos, end_pos = line:find(mention_pattern, last_pos, false)
      
      if start_pos then
        -- Add text before mention
        if start_pos > last_pos then
          local text_before = line:sub(last_pos, start_pos - 1)
          if text_before ~= "" then
            table.insert(line_content, {
              type = "text",
              text = text_before
            })
          end
        end
        
        -- Add mention node
        table.insert(line_content, {
          type = "mention",
          attrs = {
            id = account_id,
            text = "@" .. display_name
          }
        })
        
        last_pos = end_pos + 1
      end
    end
    
    -- Add remaining text after last mention
    if last_pos <= #line then
      local remaining_text = line:sub(last_pos)
      if remaining_text ~= "" then
        table.insert(line_content, {
          type = "text",
          text = remaining_text
        })
      end
    end
    
    -- If no content was added, add empty text node
    if #line_content == 0 then
      table.insert(line_content, {
        type = "text",
        text = line
      })
    end
    
    paragraph.content = line_content
    table.insert(adf.content, paragraph)
  end
  
  return adf
end

-- Show user picker for mentions
local function show_user_picker(query, callback)
  vim.notify("Searching for users: " .. query, vim.log.levels.INFO)
  
  local response = api.search_users(query)
  
  if not response or response.status ~= 200 then
    vim.notify("Failed to search users", vim.log.levels.ERROR)
    return
  end
  
  local users = vim.fn.json_decode(response.body)
  
  if not users or #users == 0 then
    vim.notify("No users found", vim.log.levels.WARN)
    return
  end
  
  -- Limit to 10 users
  local display_users = {}
  for i = 1, math.min(10, #users) do
    table.insert(display_users, users[i])
  end
  
  -- Show user picker
  local options = {}
  for _, user in ipairs(display_users) do
    local display = string.format("%s (%s)", user.displayName, user.emailAddress or "no email")
    table.insert(options, display)
  end
  
  vim.ui.select(options, {
    prompt = "Select user to mention:",
  }, function(choice, idx)
    if choice and idx then
      local selected_user = display_users[idx]
      callback(selected_user)
    end
  end)
end

-- Open comment window
function M.open_comment_window(issue_key)
  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  
  -- Set buffer options (using modern API)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  
  -- Calculate window size and position
  local width = 60
  local height = 15
  local ui = vim.api.nvim_list_uis()[1]
  local win_width = ui.width
  local win_height = ui.height
  
  local row = math.floor((win_height - height) / 2)
  local col = math.floor((win_width - width) / 2)
  
  -- Window options
  local opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Add Comment to " .. issue_key .. " ",
    title_pos = "center",
    footer = " Type @ to mention users | <CR> submit | <Esc> cancel ",
    footer_pos = "center",
  }
  
  -- Open window
  local win = vim.api.nvim_open_win(buf, true, opts)
  
  -- Set window options (using modern API)
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  
  -- Add initial instruction text
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "# Write your comment here",
    "",
    "Type @ followed by a name to mention someone.",
    "",
  })
  
  -- Move cursor to end
  vim.api.nvim_win_set_cursor(win, {4, 0})
  
  -- Enter insert mode
  vim.cmd("startinsert")
  
  -- Keymap: Escape to close
  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, noremap = true, silent = true })
  
  -- Keymap: Ctrl+C to close (in case user presses it)
  vim.keymap.set({"n", "i"}, "<C-c>", function()
    vim.api.nvim_win_close(win, true)
    vim.notify("Comment cancelled", vim.log.levels.INFO)
  end, { buffer = buf, noremap = true, silent = true })
  
  -- Keymap: @ to trigger mention
  vim.keymap.set("i", "@", function()
    -- Insert @ character
    vim.api.nvim_put({"@"}, "c", false, true)
    
    -- Prompt for user search
    vim.defer_fn(function()
      vim.ui.input({
        prompt = "Search user to mention: ",
      }, function(query)
        if query and query ~= "" then
          show_user_picker(query, function(user)
            -- Insert mention in format @[Display Name](accountId)
            local mention_text = "[" .. user.displayName .. "](" .. user.accountId .. ")"
            
            -- Get current cursor position
            local cursor_pos = vim.api.nvim_win_get_cursor(win)
            local line_num = cursor_pos[1]
            local col_num = cursor_pos[2]
            
            -- Get current line
            local line = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)[1]
            
            -- Insert mention text after @
            local new_line = line:sub(1, col_num) .. mention_text .. line:sub(col_num + 1)
            vim.api.nvim_buf_set_lines(buf, line_num - 1, line_num, false, {new_line})
            
            -- Move cursor after mention
            vim.api.nvim_win_set_cursor(win, {line_num, col_num + #mention_text})
            
            vim.notify("Mentioned " .. user.displayName, vim.log.levels.INFO)
          end)
        end
      end)
    end, 10)
  end, { buffer = buf, noremap = true, silent = true })
  
  -- Keymap: Enter in normal mode to submit
  vim.keymap.set("n", "<CR>", function()
    -- Get all lines from buffer
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local comment_text = table.concat(lines, "\n")
    
    -- Remove instruction text if still present
    comment_text = comment_text:gsub("^# Write your comment here\n+", "")
    comment_text = comment_text:gsub("Type @ followed by a name to mention someone%.\n+", "")
    
    -- Trim whitespace
    comment_text = comment_text:match("^%s*(.-)%s*$")
    
    if not comment_text or comment_text == "" then
      vim.notify("Comment cannot be empty", vim.log.levels.WARN)
      return
    end
    
    -- Close window
    vim.api.nvim_win_close(win, true)
    
    -- Parse mentions
    local mentions_map = parse_mentions(comment_text)
    
    -- Convert to ADF
    local adf = text_to_adf(comment_text, mentions_map)
    
    -- Submit comment
    vim.notify("Submitting comment to " .. issue_key .. "...", vim.log.levels.INFO)
    
    local response = api.add_comment(issue_key, adf)
    
    if response and response.status == 201 then
      vim.notify("Comment added successfully!", vim.log.levels.INFO)
      
      -- Clear cache to force refresh
      api.cache.clear_cached_issue(issue_key)
      
      -- Refresh the issue buffer if it's open
      vim.defer_fn(function()
        local ui = require("jira.ui")
        -- Find and refresh the buffer
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          local buf_name = vim.api.nvim_buf_get_name(bufnr)
          if buf_name:match("jira://" .. issue_key) then
            -- Close and reopen
            vim.api.nvim_buf_delete(bufnr, {force = true})
            ui.open_issue_in_buffer({key = issue_key})
            break
          end
        end
      end, 100)
    else
      local error_msg = "Failed to add comment"
      if response then
        error_msg = error_msg .. " (HTTP " .. (response.status or "unknown") .. ")"
        if response.body and response.body ~= "" then
          local ok, error_data = pcall(vim.fn.json_decode, response.body)
          if ok and error_data.errorMessages then
            error_msg = error_msg .. ": " .. table.concat(error_data.errorMessages, ", ")
          end
        end
      end
      vim.notify(error_msg, vim.log.levels.ERROR)
    end
  end, { buffer = buf, noremap = true, silent = true })
end

return M

