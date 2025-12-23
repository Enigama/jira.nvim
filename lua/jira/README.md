# Jira Telescope Plugin

A Neovim plugin that integrates Jira with Telescope for efficient issue management.

## Features

- 🔐 Token-based authentication via `JIRA_TOKEN` environment variable
- 🔍 Multiple search modes:
  - All Issues
  - Search by Key (e.g., PROJ-123)
  - Search by Assignee
  - Search by Text (summary/description)
  - Search by Project
  - My Issues (assigned to current user)
- 📋 Rich issue preview with:
  - Issue Type, Status, Priority
  - Summary & Description
  - Assignee & Reporter
  - Sprint, Labels, Components
  - Parent issue & Subtasks
  - Linked issues
  - Recent comments
  - Attachments
  - Browser link
- ⚡ Quick actions:
  - `<CR>` - Open issue in browser
  - `<C-y>` - Copy issue URL to clipboard
  - `<C-t>` - Transition issue status
  - `<C-a>` - Assign issue to yourself
  - `<C-r>` - Refresh cached data
- 💾 Smart caching (5 minutes for searches, 2 minutes for issue details)

## Setup

### 1. Set the JIRA_TOKEN environment variable

In your Fish shell configuration (`~/.config/fish/config.fish`):

```fish
set -x JIRA_TOKEN "your-jira-api-token-here"
```

To get your Jira API token:
1. Go to https://id.atlassian.com/manage-profile/security/api-tokens
2. Click "Create API token"
3. Give it a name (e.g., "Neovim")
4. Copy the token and set it as `JIRA_TOKEN`

**Note:** On first use, the plugin will prompt for your Jira email address (the one associated with your Atlassian account). This is required for Jira Cloud authentication and will be cached locally.

### 2. Configuration

```lua
require("jira").setup({
  jira_url = "https://your-company.atlassian.net",  -- Replace with your Jira URL
  cache_dir = vim.fn.stdpath("cache") .. "/jira",
  default_project = nil,
  max_results = 50,
  auto_refresh_interval = 300, -- 5 minutes
})
```

## Usage

### Commands

- `:JiraAuth` - Authenticate with Jira (automatic on startup if JIRA_TOKEN is set)
- `:JiraSearch` - Open search mode selector
- `:JiraMyIssues` - Show issues assigned to you
- `:JiraIssue <KEY>` - Look up a specific issue (e.g., `:JiraIssue PROJ-123`)
- `:JiraProject <KEY>` - Show all issues for a project
- `:JiraProjects` - List all projects and select one
- `:JiraLogout` - Logout from Jira
- `:JiraClearCache` - Clear cached data

### Keybindings

- `<leader>js` - Jira Search
- `<leader>ji` - Jira My Issues
- `<leader>jp` - Jira Projects
- `<leader>ja` - Jira Authenticate
- `<leader>jl` - Jira Logout
- `<leader>jc` - Jira Clear Cache

### Telescope Actions

When viewing search results in Telescope:

- `<CR>` or `Enter` - Open issue in browser
- `<C-y>` - Copy issue URL to clipboard
- `<C-t>` - Show transition picker (e.g., move to In Progress, Done, etc.)
- `<C-a>` - Assign issue to yourself
- `<C-r>` - Clear cache and refresh data

## API Structure

The plugin follows a modular architecture:

- `init.lua` - Main plugin entry point, configuration, and commands
- `auth.lua` - Authentication handling with JIRA_TOKEN
- `api.lua` - Jira REST API wrapper with caching
- `transitions.lua` - Workflow transition management
- `comments.lua` - Comment fetching and display
- `recent.lua` - Recently viewed issues tracking
- `ui/` - UI components:
  - `init.lua` - UI module entry point
  - `telescope_pickers.lua` - Telescope picker integration
  - `menus.lua` - Copy menu and action menus
  - `buffer.lua` - Issue detail buffer display
  - `format.lua` - Issue formatting utilities
  - `utils.lua` - UI helper functions

## Troubleshooting

### Authentication Failed

If you see "Failed to authenticate with Jira":
1. Verify your `JIRA_TOKEN` is set correctly: `echo $JIRA_TOKEN`
2. Make sure the token is valid (not expired)
3. Check your Jira URL is correct
4. Try running `:JiraAuth` manually

### No Issues Found

If searches return no results:
1. Verify you have access to the Jira instance
2. Check if you have permission to view issues
3. Try a broader search (e.g., "My Issues" or "All Issues")

### Network Timeout

If requests are timing out:
1. Check your internet connection
2. Verify the Jira URL is accessible
3. Check if there's a firewall/VPN issue

## Advanced Usage

### Custom JQL Queries

You can extend the plugin to support custom JQL queries by modifying `api.lua`:

```lua
-- In your custom config
local jira_api = require("jira.api")
local custom_jql = "project = PROJ AND status = 'In Progress'"
local response = jira_api.search_issues(custom_jql)
```

### Programmatic Access

Access the plugin modules programmatically:

```lua
local jira = require("jira")

-- Get current user
local user = jira.state.current_user

-- Search issues
jira.search()

-- Get specific issue
jira.get_issue("PROJ-123")
```

## Contributing

This plugin is part of the Enigama Neovim configuration. Feel free to customize it to your needs!

