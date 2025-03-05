# todo-git.nvim

Task tracking for ADHD developers using Git. Simple, distraction-free, and friction-less.

## Features

- Track tasks with a minimalist syntax
- Use Git as a history tracker
- Perfect for ADHD developers who need quick task toggles
- No complex formatting or extra keystrokes
- Automatically archive completed tasks
- Smart subtask handling

## Installation

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'jaho5/todo-git.nvim',
  config = function()
    require('todo-git').setup({
      -- Your config (all are optional)
      todo_file = 'todo.txt',           -- Main todo file
      history_dir = '.taskhistory',     -- Where completed tasks go
      git_dir = '~/.task-tracker'       -- Separate git repository
    })
    require('todo-git').init()
  end
}
```

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'jaho5/todo-git.nvim',
  config = function()
    require('todo-git').setup({
      -- Your config here
    })
    require('todo-git').init()
  end
}
```

## Usage

### Task Format

```
- Main task
  description text on multiple lines
  - Subtask
  + Completed subtask
```

- Use `-` for incomplete tasks
- Use `+` for completed tasks
- Indent lines to create descriptions or subtasks

### Keybindings

- `<Leader>c` - Toggle task completion

### Workflow

1. Edit your todo.txt file in Neovim
2. Add tasks with `-` prefix
3. Press `<Leader>c` on any line within a task to toggle its completion
4. Completed subtasks stay in the file (marked with +)
5. Completed main tasks and their completed subtasks move to archive

## Configuration

```lua
require('todo-git').setup({
  todo_file = 'todo.txt',           -- Main todo file
  history_dir = '.taskhistory',     -- Where completed tasks go
  completed_file = '.taskhistory/completed.txt', -- Archive file
  git_dir = '~/.task-tracker'       -- Separate git repository
})
```

## License

MIT
