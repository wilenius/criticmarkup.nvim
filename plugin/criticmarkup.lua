
-- CriticMarkup patterns
local patterns = {
    deletion = "{--(.-)--}",
    addition = "{%+%+(.-)%+%+}",
    substitution = "{~~(.-)~>(.-)~~}",
    highlight = "{==(.-)==}",
    comment = "{>>(.-)<<}"
}

-- accept CriticMarkup suggestions
local function process_accept(text)
    -- Remove deletions
    text = text:gsub(patterns.deletion, "")
    -- Add additions
    text = text:gsub(patterns.addition, "%1")
    -- Execute substitutions
    text = text:gsub(patterns.substitution, "%2")
    -- Remove markup code for highlights and comments
    text = text:gsub(patterns.highlight, "%1")
    text = text:gsub(patterns.comment, "%1")
    return text
end

-- decline CriticMarkup suggestions
local function process_decline(text)
    -- Retain deletions
    text = text:gsub(patterns.deletion, "%1")
    -- Do not add additions
    text = text:gsub(patterns.addition, "")
    -- Retain the original form for substitutions
    text = text:gsub(patterns.substitution, "%1")
    -- Remove highlights and comments
    text = text:gsub(patterns.highlight, "")
    text = text:gsub(patterns.comment, "")
    return text
end

local function process(args)
  -- Get the current mode
  local mode = vim.fn.mode()

  -- Check if the argument is valid
  if args[1] ~= "accept" and args[1] ~= "decline" then
    print("Invalid argument. Use 'accept' or 'decline'")
    return
  end

  -- Handle visual mode
  if mode:match("^[vV\22]") then
    -- Get visual selection
    local start_row, start_col = vim.fn.line("'<"), vim.fn.col("'<")
    local end_row, end_col = vim.fn.line("'>"), vim.fn.col("'>")

    -- Get the selected text
    local selected_lines = vim.fn.getline(start_row, end_row)

    -- Process the selected text based on the argument
    if args[1] == "accept" then
      for i, line in ipairs(selected_lines) do
        process_accept(selected_lines[i])
      end
    elseif args[1] == "decline" then
      for i, line in ipairs(selected_lines) do
        process_decline(selected_lines[i])
      end
    end

    -- Replace the selected lines with the modified text
    vim.fn.setline(start_row, end_row, selected_lines)
  elseif mode == "n" then
    -- In normal mode, process the current line
    local current_line = vim.fn.getline(".")

    -- Process the current line based on the argument
    if args[1] == "accept" then
      process_accept(current_line)
    elseif args[1] == "decline" then
      process_decline(current_line)
    end

    -- Replace the current line with the modified text
    vim.fn.setline(".", current_line)
  end
end


-- Set up mappings
vim.api.nvim_set_keymap(
  "n",
  "<LocalLeader>ca",
  ":CriticMarkup accept<CR>",
  { noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
  "v",
  "<LocalLeader>ca",
  ":'<,'>CriticMarkup accept<CR>",
  { noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
  "n",
  "<LocalLeader>cd",
  ":CriticMarkup decline<CR>",
  { noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
  "v",
  "<LocalLeader>cd",
  ":'<,'>CriticMarkup decline<CR>",
  { noremap = true, silent = true }
)

local function complete_criticmarkup(_, _, _)
  return { "accept", "decline" }
end

vim.api.nvim_create_user_command("CriticMarkup", function(opts)
  process(opts.args)
end, {
  nargs = 1,
  complete = complete_criticmarkup
})

