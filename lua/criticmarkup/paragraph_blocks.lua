local M = {}

local ns = vim.api.nvim_create_namespace("criticmarkup_paragraph_blocks")
local states = {}

local function get_state(bufnr)
  local state = states[bufnr]
  if not state then
    state = { enabled = false, blocks = {} }
    states[bufnr] = state
  end
  return state
end

local function is_editing()
  local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
  return mode == "i" or mode == "R"
end

local function characters(line, start_col, end_col)
  local result = {}
  local col = start_col
  while col < end_col do
    local char = line:sub(col + 1):match("^[%z\1-\127\194-\244][\128-\191]*")
    if not char then
      break
    end
    result[#result + 1] = { col = col, end_col = col + #char, char = char }
    col = col + #char
  end
  return result
end

local function scan(lines)
  local blocks = {}
  local row = 1

  while row <= #lines do
    if lines[row]:find("%S") then
      local paragraph_start = row - 1
      local paragraph_end = paragraph_start
      while paragraph_end + 2 <= #lines and lines[paragraph_end + 2]:find("%S") do
        paragraph_end = paragraph_end + 1
      end

      local col = lines[row]:find("%S")
      local start_col, end_col
      while col do
        local from, to = lines[row]:find("%[s%*?:%s*[^%]]-%]", col)
        if from ~= col then
          break
        end
        start_col = start_col or from - 1
        end_col = to
        col = to + 1
      end
      if start_col then
        blocks[#blocks + 1] = {
          row = paragraph_start,
          start_col = start_col,
          end_col = end_col,
          characters = characters(lines[row], start_col, end_col),
          paragraph_start = paragraph_start,
          paragraph_end = paragraph_end,
        }
      end

      row = paragraph_end + 2
    else
      row = row + 1
    end
  end

  return blocks
end

--- Redraw conceal marks, revealing blocks only in the paragraph being edited.
--- Event callbacks can supply the mode being entered or left; when omitted it
--- is derived from Neovim's current mode.
function M.update(bufnr, editing)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local state = get_state(bufnr)
  if not state.enabled then
    return
  end

  if editing == nil then
    editing = is_editing()
  end
  local cursor_row
  if editing and vim.api.nvim_get_current_buf() == bufnr then
    cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1
  end

  for _, block in ipairs(state.blocks) do
    local active = cursor_row
      and cursor_row >= block.paragraph_start
      and cursor_row <= block.paragraph_end
    if active then
      -- Markdown parses adjacent blocks as reference links and may conceal any
      -- part of them. Literal replacements above Tree-sitter's priority keep
      -- every character visible and editable.
      for _, character in ipairs(block.characters) do
        vim.api.nvim_buf_set_extmark(bufnr, ns, block.row, character.col, {
          end_row = block.row,
          end_col = character.end_col,
          conceal = character.char,
          priority = 200,
        })
      end
    else
      vim.api.nvim_buf_set_extmark(bufnr, ns, block.row, block.start_col, {
        end_row = block.row,
        end_col = block.end_col,
        conceal = "",
        priority = 110,
      })
    end
  end
end

--- Rescan paragraph blocks and redraw their conceal marks.
function M.refresh(bufnr, enabled, editing)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local state = get_state(bufnr)
  state.enabled = enabled == true
  state.blocks = state.enabled and scan(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) or {}
  M.update(bufnr, editing)
end

--- Install the mode and cursor hooks needed for an attached buffer.
function M.attach(bufnr)
  local group = vim.api.nvim_create_augroup("criticmarkup_paragraph_blocks_buf_" .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    buffer = bufnr,
    callback = function()
      M.update(bufnr, true)
    end,
  })
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    buffer = bufnr,
    callback = function()
      M.update(bufnr, false)
    end,
  })
  vim.api.nvim_create_autocmd("CursorMovedI", {
    group = group,
    buffer = bufnr,
    callback = function()
      M.update(bufnr, true)
    end,
  })
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = group,
    buffer = bufnr,
    callback = function()
      local state = get_state(bufnr)
      M.refresh(bufnr, state.enabled, true)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = bufnr,
    callback = function()
      states[bufnr] = nil
    end,
  })
end

return M
