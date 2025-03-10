-- todo-git.lua - Task tracking with Git integration

local M = {}

-- Configuration with defaults
M.config = {
  todo_file = 'todo.txt',
  history_dir = '.taskhistory',
  completed_file = '.taskhistory/completed.txt',
  git_dir = '~/.task-tracker', -- Separate git repository
}

-- Setup function for configuration
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- Ensure history directory and git repo exist
local function ensure_history_dir()
  -- Create history dir if needed
  if vim.fn.isdirectory(M.config.history_dir) == 0 then
    vim.fn.mkdir(M.config.history_dir, "p")
  end
  
  if vim.fn.filereadable(M.config.completed_file) == 0 then
    vim.fn.writefile({}, M.config.completed_file)
  end
  
  -- Ensure git repo exists
  local git_dir = vim.fn.expand(M.config.git_dir)
  if vim.fn.isdirectory(git_dir) == 0 then
    vim.fn.mkdir(git_dir, "p")
  end
  
  -- Initialize git repo if needed
  if vim.fn.isdirectory(git_dir .. "/.git") == 0 then
    vim.fn.system("git -C " .. git_dir .. " init")
  end
  
  -- Create symlinks to track files
  local todo_path = vim.fn.expand(M.config.todo_file)
  local todo_link = git_dir .. "/todo.txt"
  local history_path = vim.fn.expand(M.config.history_dir)
  local history_link = git_dir .. "/.taskhistory"
  
  if vim.fn.filereadable(todo_link) == 0 then
    vim.fn.system("ln -sf " .. todo_path .. " " .. todo_link)
  end
  
  if vim.fn.isdirectory(history_link) == 0 then
    vim.fn.system("ln -sf " .. history_path .. " " .. history_link)
  end
end

-- Check if current line is a task
local function is_task_line(line)
  line = line or vim.fn.getline(".")
  return line:match("^%s*[-+]%s")
end

-- Get task boundaries for multi-line tasks
-- Multi-line tasks are detected by indentation (leading whitespace)
local function get_task_boundaries()
  local cursor_line = vim.fn.line(".")
  local start_line = cursor_line
  local end_line = cursor_line
  local current_buf = vim.api.nvim_get_current_buf()
  
  -- Find task start (looking backward for task marker)
  while start_line > 0 do
    local line = vim.api.nvim_buf_get_lines(current_buf, start_line - 1, start_line, false)[1]
    if is_task_line(line) then
      break
    elseif line:match("^%s*$") or not line:match("^%s") then
      -- Blank line or non-indented line
      start_line = start_line + 1
      break
    end
    start_line = start_line - 1
  end
  
  -- Find task end (everything indented after the marker)
  local total_lines = vim.api.nvim_buf_line_count(current_buf)
  end_line = start_line
  
  while end_line < total_lines do
    local next_line_idx = end_line
    local next_line = vim.api.nvim_buf_get_lines(current_buf, next_line_idx, next_line_idx + 1, false)[1]
    
    if next_line:match("^%s") and not next_line:match("^%s*$") then
      -- Indented non-blank line (part of task description)
      end_line = end_line + 1
    else
      break
    end
  end
  
  return start_line, end_line
end

-- Toggle task completion
function M.toggle_task()
  local line = vim.fn.getline(".")
  
  -- If we're on a description line, find the task
  if not is_task_line(line) and line:match("^%s") then
    local start_line, _ = get_task_boundaries()
    vim.api.nvim_win_set_cursor(0, {start_line, 0})
    line = vim.fn.getline(".")
  elseif not is_task_line(line) then
    vim.api.nvim_echo({{"Not on a task line", "WarningMsg"}}, false, {})
    return
  end
  
  local start_line, end_line = get_task_boundaries()
  local task_lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  local first_line = task_lines[1]
  local indent_level = first_line:match("^(%s*)")
  
  -- Check if this is a subtask (more indented than previous task)
  local is_subtask = false
  if start_line > 1 then
    local prev_line = vim.api.nvim_buf_get_lines(0, start_line - 2, start_line - 1, false)[1]
    if is_task_line(prev_line) then
      local prev_indent = prev_line:match("^(%s*)")
      is_subtask = #indent_level > #prev_indent
    end
  end
  
  -- Toggle completion status
  if first_line:match("^%s*-%s") then
    -- Mark as completed
    task_lines[1] = first_line:gsub("^(%s*)-%s", "%1+ ")
    vim.api.nvim_buf_set_lines(0, start_line - 1, start_line, false, {task_lines[1]})
    
    if is_subtask then
      -- For subtasks, just commit the change but don't archive
      git_commit_completion(task_lines[1], true)
    else
      -- For main tasks, archive it and its completed subtasks
      archive_task(task_lines, start_line, end_line)
      git_commit_completion(task_lines[1], false)
    end
  elseif first_line:match("^%s*%+%s") then
    -- Mark as incomplete
    task_lines[1] = first_line:gsub("^(%s*)%+%s", "%1- ")
    vim.api.nvim_buf_set_lines(0, start_line - 1, start_line, false, {task_lines[1]})
    git_commit_reopening(task_lines[1])
  end
end

-- Archive a completed task
function archive_task(task_lines, start_line, end_line)
  ensure_history_dir()
  
  -- Add timestamp to completed task
  local timestamp = os.date("%Y-%m-%d %H:%M")
  local task_with_timestamp = task_lines[1] .. " [" .. timestamp .. "]"
  task_lines[1] = task_with_timestamp
  
  -- Find all completed subtasks to archive along with this task
  local buf = vim.api.nvim_get_current_buf()
  local line_count = vim.api.nvim_buf_line_count(buf)
  local next_line = end_line + 1
  local subtasks_to_archive = {}
  local main_task_indent = task_lines[1]:match("^(%s*)")
  
  -- Look for completed subtasks after this task
  while next_line <= line_count do
    local line = vim.api.nvim_buf_get_lines(buf, next_line - 1, next_line, false)[1]
    local line_indent = line:match("^(%s*)")
    
    -- If not indented more than main task, we've reached the end of subtasks
    if not line:match("^%s") or #line_indent <= #main_task_indent then
      break
    end
    
    -- If it's a completed subtask, add to archive list
    if line:match("^%s*%+%s") then
      table.insert(subtasks_to_archive, {line = next_line, text = line})
    end
    
    next_line = next_line + 1
  end
  
  -- Append to completed file
  local completed_file = M.config.completed_file
  local existing_content = {}
  
  if vim.fn.filereadable(completed_file) == 1 then
    existing_content = vim.fn.readfile(completed_file)
  end
  
  table.insert(existing_content, "")
  for _, line in ipairs(task_lines) do
    table.insert(existing_content, line)
  end
  
  -- Add completed subtasks to archive
  for _, subtask in ipairs(subtasks_to_archive) do
    table.insert(existing_content, subtask.text)
  end
  
  vim.fn.writefile(existing_content, completed_file)
  
  -- Remove task and completed subtasks from current file
  -- Remove in reverse order to avoid line number changes
  for i = #subtasks_to_archive, 1, -1 do
    vim.api.nvim_buf_set_lines(buf, subtasks_to_archive[i].line - 1, subtasks_to_archive[i].line, false, {})
  end
  
  -- Finally remove the main task
  vim.api.nvim_buf_set_lines(buf, start_line - 1, end_line, false, {})
end

-- Git commit for task completion
function git_commit_completion(task_line, is_subtask)
  local task_text = task_line:gsub("^%s*%+ (.*)", "%1"):gsub(" %[.*%]$", "")
  local commit_msg
  
  -- Get absolute paths for files
  local todo_path = vim.fn.expand(M.config.todo_file)
  local history_path = vim.fn.expand(M.config.completed_file)
  local git_path = vim.fn.expand(M.config.git_dir)
  
  if is_subtask then
    commit_msg = "Completed subtask: " .. task_text
    vim.fn.system("git -C " .. git_path .. " add " .. todo_path)
  else
    commit_msg = "Completed: " .. task_text
    vim.fn.system("git -C " .. git_path .. " add " .. todo_path .. " " .. history_path)
  end
  
  vim.fn.system("git -C " .. git_path .. " commit -m \"" .. commit_msg .. "\"")
  
  vim.api.nvim_echo({{"Committed: " .. task_text, "None"}}, false, {})
end

-- Git commit for task reopening
function git_commit_reopening(task_line)
  local task_text = task_line:gsub("^%s*- (.*)", "%1")
  local commit_msg = "Reopened: " .. task_text
  
  -- Get absolute path for todo file
  local todo_path = vim.fn.expand(M.config.todo_file)
  local git_path = vim.fn.expand(M.config.git_dir)
  
  vim.fn.system("git -C " .. git_path .. " add " .. todo_path)
  vim.fn.system("git -C " .. git_path .. " commit -m \"" .. commit_msg .. "\"")
  
  vim.api.nvim_echo({{"Committed task reopening: " .. task_text, "None"}}, false, {})
end

-- Set up keymaps
function M.set_keymaps()
  vim.api.nvim_set_keymap("n", "<Leader>x", 
    "<cmd>lua require('todo-git').toggle_task()<CR>", 
    {noremap = true, silent = true})
end

-- Initialize plugin
function M.init()
  ensure_history_dir()
  M.set_keymaps()
end

return M
