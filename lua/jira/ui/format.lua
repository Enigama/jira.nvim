local M = {}

local config = nil

function M.setup(cfg)
  config = cfg
end

-- Format issue for display in Telescope
function M.format_issue_entry(issue)
  local key = issue.key or "N/A"
  local summary = issue.fields.summary or "No summary"
  local status = issue.fields.status and issue.fields.status.name or "N/A"
  local assignee = issue.fields.assignee and issue.fields.assignee.displayName or "Unassigned"
  
  return string.format("[%s] %s | %s | %s", key, status, summary, assignee)
end

-- Format Atlassian Document Format (ADF) to plain text
function M.format_adf_text(adf)
  -- Handle string
  if type(adf) == "string" then
    return adf
  end
  
  -- Handle userdata, number, boolean, or nil - these are not valid ADF
  if type(adf) ~= "table" then
    return ""
  end
  
  -- Now safe to check table properties
  if not adf.content then
    return ""
  end
  
  local lines = {}
  
  local function process_node(node)
    -- Ensure node is a table
    if type(node) ~= "table" then
      return
    end
    
    if node.type == "paragraph" then
      local text = ""
      if node.content and type(node.content) == "table" then
        for _, child in ipairs(node.content) do
          if type(child) == "table" and child.type == "text" then
            text = text .. (child.text or "")
          end
        end
      end
      table.insert(lines, text)
    elseif node.type == "text" then
      return node.text or ""
    elseif node.content and type(node.content) == "table" then
      for _, child in ipairs(node.content) do
        process_node(child)
      end
    end
  end
  
  -- Ensure adf.content is iterable
  if type(adf.content) == "table" then
    for _, node in ipairs(adf.content) do
      process_node(node)
    end
  end
  
  return table.concat(lines, "\n")
end

-- Format issue content as markdown
function M.format_issue_as_markdown(issue)
  -- Validate input
  if not issue then
    vim.notify("Error: Issue data is nil", vim.log.levels.ERROR)
    return {"# Error: Issue data is missing", "", "The issue data could not be loaded."}
  end
  
  if not issue.fields then
    vim.notify("Error: Issue fields are missing for " .. (issue.key or "unknown"), vim.log.levels.ERROR)
    return {"# Error: Issue fields missing", "", "The issue fields could not be loaded."}
  end
  
  -- Safe field access that handles userdata and nil
  local function safe_get(obj, field, default)
    if type(obj) ~= "table" then
      return default or "N/A"
    end
    local value = obj[field]
    if value == nil or type(value) == "userdata" then
      return default or "N/A"
    end
    return value
  end
  
  local lines = {}
  local fields = issue.fields
  
  -- Title
  table.insert(lines, "# [" .. (issue.key or "N/A") .. "] " .. (fields.summary or "No summary"))
  table.insert(lines, "")
  
  -- Metadata
  local status = fields.status and fields.status.name or "N/A"
  local priority = fields.priority and fields.priority.name or "N/A"
  local issue_type = fields.issuetype and fields.issuetype.name or "N/A"
  table.insert(lines, "**Status:** " .. status .. " | **Priority:** " .. priority .. " | **Type:** " .. issue_type)
  
  local assignee = fields.assignee and fields.assignee.displayName or "Unassigned"
  local reporter = fields.reporter and fields.reporter.displayName or "N/A"
  table.insert(lines, "**Assignee:** " .. assignee .. " | **Reporter:** " .. reporter)
  
  -- Add story points check (common custom fields for story points)
  -- Try multiple common custom field names
  local story_points = fields.customfield_10016 
                    or fields.customfield_10026 
                    or fields.customfield_10002
                    or fields.customfield_10004
                    or fields.customfield_10028
                    or fields.storyPoints
  
  -- Debug: Log all custom fields to help identify the correct one
  if not story_points or type(story_points) == "userdata" then
    pcall(function()
      for key, value in pairs(fields) do
        if key:match("^customfield_") and value and type(value) == "number" then
          -- Use the first numeric custom field we find
          if not story_points or type(story_points) == "userdata" then
            story_points = value
          end
        end
      end
    end)
  end
  
  local story_points_display = "N/A"
  if story_points and type(story_points) ~= "userdata" then
    story_points_display = tostring(story_points)
  end
  table.insert(lines, "**Story Points:** " .. story_points_display)
  
  table.insert(lines, "")
  
  -- Sprint
  if fields.sprint and type(fields.sprint) == "table" then
    table.insert(lines, "**Sprint:** " .. safe_get(fields.sprint, "name"))
    table.insert(lines, "")
  end
  
  -- Labels
  if fields.labels and type(fields.labels) == "table" and #fields.labels > 0 then
    -- Filter out any non-string labels
    local valid_labels = {}
    for _, label in ipairs(fields.labels) do
      if type(label) == "string" then
        table.insert(valid_labels, label)
      end
    end
    if #valid_labels > 0 then
      table.insert(lines, "**Labels:** " .. table.concat(valid_labels, ", "))
      table.insert(lines, "")
    end
  end
  
  -- Components
  if fields.components and type(fields.components) == "table" and #fields.components > 0 then
    local comp_names = {}
    for _, comp in ipairs(fields.components) do
      if type(comp) == "table" and comp.name then
        table.insert(comp_names, comp.name)
      end
    end
    if #comp_names > 0 then
      table.insert(lines, "**Components:** " .. table.concat(comp_names, ", "))
      table.insert(lines, "")
    end
  end
  
  -- Parent issue
  if fields.parent and type(fields.parent) == "table" then
    local parent_key = safe_get(fields.parent, "key", "N/A")
    local parent_summary = ""
    if type(fields.parent.fields) == "table" then
      parent_summary = safe_get(fields.parent.fields, "summary", "")
    end
    table.insert(lines, "**Parent:** [" .. parent_key .. "] " .. parent_summary)
    table.insert(lines, "")
  end
  
  -- Description
  table.insert(lines, "## Description")
  table.insert(lines, "")
  if fields.description then
    local desc = M.format_adf_text(fields.description)
    for _, line in ipairs(vim.split(desc, "\n")) do
      table.insert(lines, line)
    end
  else
    table.insert(lines, "_No description_")
  end
  table.insert(lines, "")
  
  -- Subtasks
  if fields.subtasks and type(fields.subtasks) == "table" and #fields.subtasks > 0 then
    table.insert(lines, "## Subtasks")
    table.insert(lines, "")
    for _, subtask in ipairs(fields.subtasks) do
      if type(subtask) == "table" then
        local subtask_key = safe_get(subtask, "key", "N/A")
        local subtask_status = "N/A"
        local subtask_summary = "N/A"
        
        if type(subtask.fields) == "table" then
          if type(subtask.fields.status) == "table" then
            subtask_status = safe_get(subtask.fields.status, "name", "N/A")
          end
          subtask_summary = safe_get(subtask.fields, "summary", "N/A")
        end
        
        table.insert(lines, "- [" .. subtask_key .. "] **" .. subtask_status .. "** - " .. subtask_summary)
      end
    end
    table.insert(lines, "")
  end
  
  -- Linked issues
  if fields.issuelinks and type(fields.issuelinks) == "table" and #fields.issuelinks > 0 then
    table.insert(lines, "## Linked Issues")
    table.insert(lines, "")
    for _, link in ipairs(fields.issuelinks) do
      if type(link) == "table" then
        local linked_issue = link.outwardIssue or link.inwardIssue
        if linked_issue and type(linked_issue) == "table" then
          local link_type = "N/A"
          if type(link.type) == "table" then
            link_type = link.type.outward or link.type.inward or "N/A"
          end
          
          local linked_key = safe_get(linked_issue, "key", "N/A")
          local linked_summary = "N/A"
          if type(linked_issue.fields) == "table" then
            linked_summary = safe_get(linked_issue.fields, "summary", "N/A")
          end
          
          table.insert(lines, "- **" .. link_type .. ":** [" .. linked_key .. "] " .. linked_summary)
        end
      end
    end
    table.insert(lines, "")
  end
  
  -- Comments
  if fields.comment and type(fields.comment) == "table" and 
     fields.comment.comments and type(fields.comment.comments) == "table" and 
     #fields.comment.comments > 0 then
    table.insert(lines, "## Comments")
    table.insert(lines, "")
    local comments = fields.comment.comments
    for i = 1, #comments do
      local comment = comments[i]
      if type(comment) == "table" then
        local author = "Unknown"
        if type(comment.author) == "table" then
          author = safe_get(comment.author, "displayName", "Unknown")
        end
        
        local created = "N/A"
        if type(comment.created) == "string" and #comment.created >= 10 then
          created = comment.created:sub(1, 10)
        end
        
        table.insert(lines, "### " .. author .. " (" .. created .. ")")
        table.insert(lines, "")
        
        local comment_text = M.format_adf_text(comment.body)
        for _, line in ipairs(vim.split(comment_text, "\n")) do
          table.insert(lines, line)
        end
        table.insert(lines, "")
      end
    end
  end
  
  -- Attachments
  if fields.attachment and type(fields.attachment) == "table" and #fields.attachment > 0 then
    table.insert(lines, "## Attachments")
    table.insert(lines, "")
    for _, att in ipairs(fields.attachment) do
      if type(att) == "table" then
        local mime_type = att.mimeType or ""
        local icon = mime_type:match("^image/") and "🖼️ " or "📎 "
        local filename = safe_get(att, "filename", "unknown")
        local size = att.size or 0
        table.insert(lines, "- " .. icon .. filename .. " (" .. size .. " bytes)")
        if att.content and type(att.content) == "string" then
          table.insert(lines, "  URL: " .. att.content)
        end
      end
    end
    table.insert(lines, "")
  end
  
  -- Footer with URL
  table.insert(lines, "---")
  local url = config.jira_url .. "/browse/" .. issue.key
  table.insert(lines, "**URL:** " .. url)
  table.insert(lines, "")
  table.insert(lines, "_Press `q` to close | `<C-t>` transition | `<C-a>` assign | `<C-o>` open in browser | `<C-y>` copy | `<C-r>` refresh | `<C-c>` comment_")
  
  return lines
end

return M

