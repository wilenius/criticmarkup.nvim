-- criticmarkup.nvim — CriticMarkup highlighting and processing for Neovim.

local M = {}

local ns = vim.api.nvim_create_namespace("criticmarkup")

M.config = {
  highlight = true,
  -- Conceal the markup delimiters (respects 'conceallevel', so nothing is
  -- hidden unless conceallevel > 0).
  conceal = true,
  filetypes = { "markdown", "pandoc", "text" },
  default_mappings = true,
}

-- Lua patterns for the five CriticMarkup annotation types. All delimiters
-- are three bytes long, which resolve() and decorate() rely on. `.-` also
-- matches newlines, so annotations spanning lines are handled.
local patterns = {
  addition = "{%+%+.-%+%+}",
  deletion = "{%-%-.-%-%-}",
  substitution = "{~~.-~>.-~~}",
  highlight = "{==.-==}",
  comment = "{>>.-<<}",
}

local content_hl = {
  addition = "CriticAddition",
  deletion = "CriticDeletion",
  highlight = "CriticHighlight",
  comment = "CriticComment",
}

-- Whole-buffer text as one string, plus 1-based byte offsets of each line
-- start so annotation offsets can be mapped back to buffer positions.
local function buf_text(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local offsets = { 1 }
  for i = 2, #lines do
    offsets[i] = offsets[i - 1] + #lines[i - 1] + 1
  end
  return table.concat(lines, "\n"), offsets, lines
end

-- Map a 1-based byte offset to a (0-based row, 0-based col) position.
local function to_pos(offsets, offset)
  local lo, hi = 1, #offsets
  while lo < hi do
    local mid = math.ceil((lo + hi) / 2)
    if offsets[mid] <= offset then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return lo - 1, offset - offsets[lo]
end

-- All annotations in the text, sorted by position. Fields: kind, from/to
-- (1-based inclusive byte offsets) and sep (offset of "~>", substitutions).
local function scan(text)
  local anns = {}
  for kind, pat in pairs(patterns) do
    local init = 1
    while true do
      local from, to = text:find(pat, init)
      if not from then
        break
      end
      local ann = { kind = kind, from = from, to = to }
      if kind == "substitution" then
        ann.sep = text:find("~>", from + 3, true)
      end
      anns[#anns + 1] = ann
      init = to + 1
    end
  end
  table.sort(anns, function(a, b)
    return a.from < b.from
  end)
  -- Malformed input can make different kinds overlap; keep the earliest
  -- annotation and drop anything starting inside it.
  local result, last_to = {}, 0
  for _, ann in ipairs(anns) do
    if ann.from > last_to then
      result[#result + 1] = ann
      last_to = ann.to
    end
  end
  return result
end

-- The text an annotation resolves to when accepted or rejected.
local function resolve(text, kind, action)
  local inner = text:sub(4, -4)
  if kind == "addition" then
    return action == "accept" and inner or ""
  elseif kind == "deletion" then
    return action == "accept" and "" or inner
  elseif kind == "substitution" then
    local old, new = inner:match("^(.-)~>(.*)$")
    return action == "accept" and new or old
  elseif kind == "highlight" then
    -- A highlight is not a proposed change: both actions keep the text.
    return inner
  end
  return "" -- comment: metadata, dropped either way
end

local function apply(bufnr, offsets, text, ann, action)
  local srow, scol = to_pos(offsets, ann.from)
  local erow, ecol = to_pos(offsets, ann.to)
  local replacement = resolve(text:sub(ann.from, ann.to), ann.kind, action)
  vim.api.nvim_buf_set_text(bufnr, srow, scol, erow, ecol + 1, vim.split(replacement, "\n", { plain = true }))
end

local function resolve_at_cursor(action)
  local bufnr = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local text, offsets = buf_text(bufnr)
  local cursor = offsets[row] + col
  for _, ann in ipairs(scan(text)) do
    if ann.from > cursor then
      break
    end
    if cursor <= ann.to then
      apply(bufnr, offsets, text, ann, action)
      M.refresh(bufnr)
      return
    end
  end
  vim.notify("criticmarkup: no annotation under cursor", vim.log.levels.INFO)
end

local function resolve_range(action, line1, line2)
  local bufnr = vim.api.nvim_get_current_buf()
  local text, offsets, lines = buf_text(bufnr)
  local from = offsets[line1]
  local to = offsets[line2] + #lines[line2] - 1
  local anns = scan(text)
  -- Apply back to front so earlier offsets stay valid.
  for i = #anns, 1, -1 do
    local ann = anns[i]
    if ann.from <= to and ann.to >= from then
      apply(bufnr, offsets, text, ann, action)
    end
  end
  M.refresh(bufnr)
end

--- Accept the annotation under the cursor.
function M.accept()
  resolve_at_cursor("accept")
end

--- Reject the annotation under the cursor.
function M.reject()
  resolve_at_cursor("reject")
end

--- Accept every annotation overlapping the given 1-based line range.
function M.accept_range(line1, line2)
  resolve_range("accept", line1, line2)
end

--- Reject every annotation overlapping the given 1-based line range.
function M.reject_range(line1, line2)
  resolve_range("reject", line1, line2)
end

-- Highlighting ---------------------------------------------------------

local function extmark(bufnr, offsets, from, to, hl, conceal, priority)
  if to < from then
    return -- empty annotation body
  end
  local srow, scol = to_pos(offsets, from)
  local erow, ecol = to_pos(offsets, to)
  vim.api.nvim_buf_set_extmark(bufnr, ns, srow, scol, {
    end_row = erow,
    end_col = ecol + 1,
    hl_group = hl,
    conceal = conceal and "" or nil,
    priority = priority or 110, -- above treesitter (100)
  })
end

local function decorate(bufnr, offsets, ann)
  local conceal = M.config.conceal
  if ann.kind == "substitution" and ann.sep then
    extmark(bufnr, offsets, ann.from, ann.from + 2, "CriticDeletion", conceal)
    extmark(bufnr, offsets, ann.from + 3, ann.sep - 1, "CriticDeletion", false)
    -- A substitution's "~~" delimiters also read as a markdown strikethrough
    -- run, so the markdown parser strikes the whole annotation through. Our
    -- extmarks sit above it, but attributes are merged rather than replaced,
    -- so the replacement would keep the strike; CriticIgnore is `nocombine`,
    -- which drops whatever is underneath it. It sits below the marks carrying
    -- the colours so those still apply.
    extmark(bufnr, offsets, ann.sep, ann.to, "CriticIgnore", false, 109)
    extmark(bufnr, offsets, ann.sep, ann.sep + 1, "CriticMarker", false)
    extmark(bufnr, offsets, ann.sep + 2, ann.to - 3, "CriticAddition", false)
    extmark(bufnr, offsets, ann.to - 2, ann.to, "CriticAddition", conceal)
  else
    local hl = content_hl[ann.kind]
    extmark(bufnr, offsets, ann.from, ann.from + 2, hl, conceal)
    extmark(bufnr, offsets, ann.from + 3, ann.to - 3, hl, false)
    extmark(bufnr, offsets, ann.to - 2, ann.to, hl, conceal)
  end
end

--- Rescan the buffer and redraw all annotation highlights.
function M.refresh(bufnr)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  if not M.config.highlight then
    return
  end
  local text, offsets = buf_text(bufnr)
  for _, ann in ipairs(scan(text)) do
    decorate(bufnr, offsets, ann)
  end
end

-- Navigation -----------------------------------------------------------

local jump_pattern = [[{\(++\|--\|==\|>>\|\~\~\)]]

--- Jump to the [count]th next annotation.
function M.next()
  for i = 1, vim.v.count1 do
    vim.fn.search(jump_pattern, i == 1 and "s" or "")
  end
end

--- Jump to the [count]th previous annotation.
function M.prev()
  for i = 1, vim.v.count1 do
    vim.fn.search(jump_pattern, i == 1 and "bs" or "b")
  end
end

-- Creating annotations --------------------------------------------------

local wrap_delims = {
  addition = { "{++", "++}" },
  deletion = { "{--", "--}" },
  substitution = { "{~~", "~>~~}" },
  comment = { "{>>", "<<}" },
  highlight = { "{==", "==}" },
}

local pending_kind

-- from/to are (1-based row, 0-based byte col) mark positions; for charwise
-- regions `to` points at the first byte of the last character.
local function wrap_region(motion, from, to, kind)
  local open, close = unpack(wrap_delims[kind])
  local srow, scol = from[1], from[2]
  local erow, ecol = to[1], to[2]
  if motion == "line" then
    vim.api.nvim_buf_set_lines(0, erow, erow, false, { close })
    vim.api.nvim_buf_set_lines(0, srow - 1, srow - 1, false, { open })
    if kind == "substitution" then
      vim.api.nvim_win_set_cursor(0, { erow + 2, 2 })
    end
  else
    local line = vim.api.nvim_buf_get_lines(0, erow - 1, erow, false)[1]
    local endcol = ecol
    if #line > 0 then
      -- step over the (possibly multibyte) character under the end mark
      local char = line:sub(ecol + 1):match("^[%z\1-\127\194-\244][\128-\191]*")
      endcol = ecol + (char and #char or 1)
    end
    vim.api.nvim_buf_set_text(0, erow - 1, endcol, erow - 1, endcol, { close })
    vim.api.nvim_buf_set_text(0, srow - 1, scol, srow - 1, scol, { open })
    if kind == "substitution" then
      -- place the cursor between "~>" and "~~}", where the new text goes
      local shift = (srow == erow) and #open or 0
      vim.api.nvim_win_set_cursor(0, { erow, endcol + shift + 2 })
    end
  end
end

--- Operator that wraps a motion in the given annotation kind. Use from an
--- expression mapping: it returns "g@".
function M.annotate(kind)
  pending_kind = kind
  vim.go.operatorfunc = "v:lua.require'criticmarkup'._opfunc"
  return "g@"
end

function M._opfunc(motion)
  wrap_region(motion, vim.api.nvim_buf_get_mark(0, "["), vim.api.nvim_buf_get_mark(0, "]"), pending_kind)
end

--- Wrap the current visual selection in the given annotation kind.
function M.annotate_visual(kind)
  local mode = vim.fn.mode()
  if mode == "\22" then
    vim.notify("criticmarkup: blockwise selections are not supported", vim.log.levels.WARN)
    return
  end
  -- Leave visual mode so the '< and '> marks are set for this selection.
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  local from = vim.api.nvim_buf_get_mark(0, "<")
  local to = vim.api.nvim_buf_get_mark(0, ">")
  wrap_region(mode == "V" and "line" or "char", from, to, kind)
end

-- Setup ------------------------------------------------------------------

local function set_mappings(bufnr)
  local function map(mode, lhs, rhs, desc, opts)
    vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", { buffer = bufnr, silent = true, desc = desc }, opts or {}))
  end
  map("n", "<LocalLeader>ca", M.accept, "CriticMarkup: accept annotation")
  map("n", "<LocalLeader>cr", M.reject, "CriticMarkup: reject annotation")
  map("x", "<LocalLeader>ca", ":CriticMarkup accept<CR>", "CriticMarkup: accept annotations in range")
  map("x", "<LocalLeader>cr", ":CriticMarkup reject<CR>", "CriticMarkup: reject annotations in range")
  map("n", "]m", M.next, "CriticMarkup: next annotation")
  map("n", "[m", M.prev, "CriticMarkup: previous annotation")
  for key, kind in pairs({ ea = "addition", ed = "deletion", es = "substitution", ec = "comment", eh = "highlight" }) do
    map("n", "<LocalLeader>" .. key, function()
      return M.annotate(kind)
    end, "CriticMarkup: " .. kind .. " (operator)", { expr = true })
    map("x", "<LocalLeader>" .. key, function()
      M.annotate_visual(kind)
    end, "CriticMarkup: " .. kind .. " (selection)")
  end
end

--- Enable highlighting and mappings for a buffer. Called automatically for
--- the configured filetypes; call directly to attach any other buffer.
function M.attach(bufnr)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if vim.b[bufnr].criticmarkup then
    return
  end
  vim.b[bufnr].criticmarkup = true
  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
    group = vim.api.nvim_create_augroup("criticmarkup_buf_" .. bufnr, { clear = true }),
    buffer = bufnr,
    callback = function()
      M.refresh(bufnr)
    end,
  })
  M.refresh(bufnr)
  if M.config.default_mappings then
    set_mappings(bufnr)
  end
end

function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.b[bufnr].criticmarkup then
      M.refresh(bufnr)
    end
  end
end

return M
