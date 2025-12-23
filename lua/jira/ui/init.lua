local M = {}

-- Load submodules
local utils = require("jira.ui.utils")
local format = require("jira.ui.format")
local menus = require("jira.ui.menus")
local buffer = require("jira.ui.buffer")
local telescope_pickers = require("jira.ui.telescope_pickers")

function M.setup(cfg)
  -- Initialize all submodules
  utils.setup(cfg)
  format.setup(cfg)
  menus.setup(cfg)
  buffer.setup(cfg)
  telescope_pickers.setup(cfg)
end

-- Public API - delegates to appropriate modules

-- Main search and picker functions
M.search_issues = telescope_pickers.search_issues
M.show_telescope_picker = telescope_pickers.show_issue_picker
M.my_issues_with_status_filter = telescope_pickers.my_issues_with_status_filter
M.show_recent_issue = telescope_pickers.show_recent_issue

-- Buffer operations
M.open_issue_in_buffer = buffer.open_issue_in_buffer

-- Formatting functions (exposed for external use)
M.format_adf_text = format.format_adf_text
M.format_issue_entry = format.format_issue_entry
M.format_issue_as_markdown = format.format_issue_as_markdown

-- Menu functions (exposed for external use)
M.show_copy_menu = menus.show_copy_menu
M.assign_to_self = menus.assign_to_self

-- Utility functions (exposed for external use)
M.open_in_browser = utils.open_in_browser
M.copy_to_clipboard = utils.copy_to_clipboard

return M

