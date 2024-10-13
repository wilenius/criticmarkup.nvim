-- CriticMarkup patterns
local patterns = {
    deletion = "{%-%-(.-)%-%-}",
    addition = "{%+%+(.-)%+%+}",
    substitution = "{%~%~(.-)%~>(.-)%~%~}",
    highlight = "{%=%=(.-)%=%=}",
    comment = "{%>%>(.-)%<%<}"
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

-- reject CriticMarkup suggestions
local function process_reject(text)
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

-- Process single match under cursor
local function process_single_match(line, col, process_func)
    local new_line = line
    for pattern, _ in pairs(patterns) do
        local s, e = line:find(patterns[pattern])
        if s and col >= s and col <= e then
            new_line = process_func(line:sub(s, e))
            new_line = line:sub(1, s-1) .. new_line .. line:sub(e+1)
            break
        end
    end
    return new_line
end

local function process(args)
    -- Get the current mode
    local mode = vim.fn.mode()

    -- Check if the argument is valid
    if args ~= "accept" and args ~= "reject" then
        print("Invalid argument. Use 'accept' or 'reject'")
        return
    end

    local process_func = args == "accept" and process_accept or process_reject

    -- Handle visual mode
    if mode:match("^[vV\22]") then
        -- Get visual selection
        local start_row, start_col = vim.fn.line("'<"), vim.fn.col("'<")
        local end_row, end_col = vim.fn.line("'>"), vim.fn.col("'>")

        -- Get the selected text
        local selected_lines = vim.fn.getline(start_row, end_row)

        -- Process the selected text based on the argument
        for i, line in ipairs(selected_lines) do
            if i == 1 and i == #selected_lines then
                -- Single line selection
                selected_lines[i] = process_single_match(line, start_col, process_func)
            elseif i == 1 then
                -- First line in multi-line selection
                selected_lines[i] = process_single_match(line, start_col, process_func)
            elseif i == #selected_lines then
                -- Last line in multi-line selection
                selected_lines[i] = process_single_match(line, end_col, process_func)
            else
                -- Full lines in between
                selected_lines[i] = process_func(line)
            end
        end

        -- Replace the selected lines with the modified text
        vim.fn.setline(start_row, selected_lines)
    elseif mode == "n" then
        -- In normal mode, process the current line
        local current_line = vim.fn.getline(".")
        local col = vim.fn.col(".")
        current_line = process_single_match(current_line, col, process_func)
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
  "<LocalLeader>cr",
  ":CriticMarkup reject<CR>",
  { noremap = true, silent = true }
)
vim.api.nvim_set_keymap(
  "v",
  "<LocalLeader>cr",
  ":'<,'>CriticMarkup reject<CR>",
  { noremap = true, silent = true }
)

local function complete_criticmarkup(_, _, _)
  return { "accept", "reject" }
end

vim.api.nvim_create_user_command("CriticMarkup", function(opts)
  process(opts.args)
end, {
  nargs = 1,
  complete = complete_criticmarkup
  })
