# jira.nvim

A powerful Neovim plugin for Jira integration with Telescope.

## Features

- 🔐 **Token-based authentication** via `JIRA_TOKEN` environment variable
- 🔍 **Multiple search modes**: By key, assignee, text, project, or show all your issues
- 📋 **Rich issue preview**: See full details including description, comments, attachments, links
- ⚡ **Quick actions**:
  - Open issues in browser
  - Copy in 6 different formats (key, URL, Markdown, Slack, etc.)
  - Transition issue status
  - Assign issues to yourself
- 🔄 **Status filtering**: Cycle through statuses (In Progress, Backlog, Ready for Dev, Ready for QA, All)
- 💾 **Smart caching**: Fast response times with intelligent caching

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  "Enigama/jira.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
  },
  config = function()
    require("jira").setup({
      jira_url = "https://your-company.atlassian.net",
      max_results = 10,
      auto_refresh_interval = 300, -- 5 minutes
    })
  end,
  lazy = true,
  cmd = {
    "JiraAuth",
    "JiraSearch",
    "JiraIssue",
    "JiraMyIssues",
    "JiraProject",
    "JiraProjects",
    "JiraLogout",
    "JiraClearCache",
  },
  keys = {
    { "<leader>js", "<cmd>JiraSearch<cr>", desc = "Jira: Search" },
    { "<leader>ji", "<cmd>JiraMyIssues<cr>", desc = "Jira: My Issues" },
    { "<leader>jp", "<cmd>JiraProjects<cr>", desc = "Jira: Projects" },
    { "<leader>ja", "<cmd>JiraAuth<cr>", desc = "Jira: Authenticate" },
    { "<leader>jl", "<cmd>JiraLogout<cr>", desc = "Jira: Logout" },
    { "<leader>jc", "<cmd>JiraClearCache<cr>", desc = "Jira: Clear Cache" },
  },
}
```

## Setup

### 1. Get Your Jira API Token

1. Go to https://id.atlassian.com/manage-profile/security/api-tokens
2. Click "Create API token"
3. Give it a name (e.g., "Neovim")
4. Copy the token

### 2. Set Environment Variable

Add to your shell configuration (e.g., `~/.config/fish/config.fish`):

```fish
set -x JIRA_TOKEN "your-api-token-here"
```

### 3. Use the Plugin

On first use, you'll be prompted for your Jira email address. This will be cached locally.

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:JiraMyIssues` | Show your assigned issues (with status filter) |
| `:JiraSearch` | Open search with mode selector |
| `:JiraIssue <KEY>` | Look up specific issue |
| `:JiraProjects` | List all projects |
| `:JiraAuth` | Authenticate with Jira |
| `:JiraLogout` | Logout and clear cached credentials |
| `:JiraClearCache` | Clear cached issue data |

### Keybindings

**Global:**
- `<leader>ji` - My Issues (most common)
- `<leader>js` - Search
- `<leader>jp` - Projects
- `<leader>ja` - Authenticate
- `<leader>jc` - Clear Cache

**In Telescope Picker:**
- `<Enter>` - Open issue in browser
- `<C-y>` - Show copy menu (6 formats)
- `<C-t>` - Transition issue status
- `<C-a>` - Assign to yourself
- `<C-r>` - Refresh data
- `<C-s>` / `<C-b>` - Cycle status forward/backward (My Issues only)

### Copy Menu

Press `<C-y>` in any picker to see copy options:

1. **Ticket key only** - `PROJ-123`
2. **Full URL** - `https://jira.../PROJ-123`
3. **Markdown link** - `[PROJ-123](https://...)`
4. **Ticket title** - `Fix authentication bug`
5. **Key + Title** - `PROJ-123 - Fix authentication bug`
6. **Slack format** - `<https://...|PROJ-123>`

## Requirements

- Neovim >= 0.8.0
- [Telescope](https://github.com/nvim-telescope/telescope.nvim)
- [Plenary](https://github.com/nvim-lua/plenary.nvim)
- `curl` command-line tool
- Jira Cloud account with API access

## Configuration

```lua
require("jira").setup({
  jira_url = "https://your-company.atlassian.net",  -- Your Jira instance
  cache_dir = vim.fn.stdpath("cache") .. "/jira",   -- Cache directory
  default_project = nil,                             -- Optional: filter to specific project
  max_results = 10,                                  -- Max issues per search
  auto_refresh_interval = 300,                       -- Cache TTL in seconds (5 minutes)
})
```

## Troubleshooting

### Authentication Failed

- Verify `JIRA_TOKEN` is set: `echo $JIRA_TOKEN`
- Check your email is correct: Run `:JiraLogout` then `:JiraAuth`
- Generate new token if expired

### No Issues Found

- Try broader search (My Issues → cycle to "All" with `<C-s>`)
- Clear cache: `<leader>jc`
- Check Jira permissions

## Contributing

This plugin is part of a personal Neovim configuration. Feel free to fork and customize!

## License

MIT License - See [LICENSE](LICENSE) file

## Credits

Built with ❤️ using:
- [Telescope](https://github.com/nvim-telescope/telescope.nvim)
- [Plenary](https://github.com/nvim-lua/plenary.nvim)
- Jira REST API v3

