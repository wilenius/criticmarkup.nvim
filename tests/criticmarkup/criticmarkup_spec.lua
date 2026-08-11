local cm = require("criticmarkup")

local function set_buf(lines)
  vim.cmd("enew!")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

local function get_buf()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function paragraph_marks()
  local ns = vim.api.nvim_create_namespace("criticmarkup_paragraph_blocks")
  return vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
end

local function revealed_text(marks, row)
  local chars = {}
  for _, mark in ipairs(marks) do
    if mark[2] == row and mark[4].conceal ~= "" then
      chars[#chars + 1] = mark[4].conceal
    end
  end
  return table.concat(chars)
end

describe("accept at cursor", function()
  it("keeps addition text", function()
    set_buf({ "one {++added++} word" })
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
    cm.accept()
    assert.are.same({ "one added word" }, get_buf())
  end)

  it("removes deletion", function()
    set_buf({ "two {--deleted --}word" })
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
    cm.accept()
    assert.are.same({ "two word" }, get_buf())
  end)

  it("applies substitution", function()
    set_buf({ "the {~~bird~>condor~~} flew" })
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
    cm.accept()
    assert.are.same({ "the condor flew" }, get_buf())
  end)

  it("strips highlight markup, keeping text", function()
    set_buf({ "a {==marked==} word" })
    vim.api.nvim_win_set_cursor(0, { 1, 5 })
    cm.accept()
    assert.are.same({ "a marked word" }, get_buf())
  end)

  it("removes comment entirely", function()
    set_buf({ "done.{>> really? <<}" })
    vim.api.nvim_win_set_cursor(0, { 1, 8 })
    cm.accept()
    assert.are.same({ "done." }, get_buf())
  end)

  it("finds the second annotation on a line", function()
    set_buf({ "{++first++} and {++second++} end" })
    vim.api.nvim_win_set_cursor(0, { 1, 19 })
    cm.accept()
    assert.are.same({ "{++first++} and second end" }, get_buf())
  end)

  it("handles annotations spanning lines", function()
    set_buf({ "a {++x", "y++} b" })
    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    cm.accept()
    assert.are.same({ "a x", "y b" }, get_buf())
  end)

  it("leaves the buffer alone when there is no annotation", function()
    set_buf({ "plain text" })
    vim.api.nvim_win_set_cursor(0, { 1, 2 })
    cm.accept()
    assert.are.same({ "plain text" }, get_buf())
  end)
end)

describe("reject at cursor", function()
  it("removes addition", function()
    set_buf({ "one {++added ++}word" })
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
    cm.reject()
    assert.are.same({ "one word" }, get_buf())
  end)

  it("keeps deletion text", function()
    set_buf({ "two {--deleted--} word" })
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
    cm.reject()
    assert.are.same({ "two deleted word" }, get_buf())
  end)

  it("keeps the original in substitution", function()
    set_buf({ "the {~~bird~>condor~~} flew" })
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
    cm.reject()
    assert.are.same({ "the bird flew" }, get_buf())
  end)

  it("strips highlight markup, keeping text", function()
    set_buf({ "a {==marked==} word" })
    vim.api.nvim_win_set_cursor(0, { 1, 5 })
    cm.reject()
    assert.are.same({ "a marked word" }, get_buf())
  end)
end)

describe("range processing", function()
  it("resolves every annotation in the range and nothing outside it", function()
    set_buf({
      "1 {++a++} {--b--}",
      "2 {~~c~>d~~}",
      "3 {++outside++}",
    })
    cm.accept_range(1, 2)
    assert.are.same({ "1 a ", "2 d", "3 {++outside++}" }, get_buf())
  end)
end)

describe("navigation", function()
  it("jumps to next and previous annotations", function()
    set_buf({ "plain", "x {--del--}", "y {++add++}" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    cm.next()
    assert.are.same({ 2, 2 }, vim.api.nvim_win_get_cursor(0))
    cm.next()
    assert.are.same({ 3, 2 }, vim.api.nvim_win_get_cursor(0))
    cm.prev()
    assert.are.same({ 2, 2 }, vim.api.nvim_win_get_cursor(0))
  end)
end)

describe("creating annotations", function()
  it("wraps a charwise region", function()
    set_buf({ "delete this word" })
    cm.annotate("deletion")
    vim.api.nvim_buf_set_mark(0, "[", 1, 7, {})
    vim.api.nvim_buf_set_mark(0, "]", 1, 10, {})
    cm._opfunc("char")
    assert.are.same({ "delete {--this--} word" }, get_buf())
  end)

  it("wraps lines and positions the cursor for substitutions", function()
    set_buf({ "first", "second" })
    cm.annotate("substitution")
    vim.api.nvim_buf_set_mark(0, "[", 1, 0, {})
    vim.api.nvim_buf_set_mark(0, "]", 2, 0, {})
    cm._opfunc("line")
    assert.are.same({ "{~~", "first", "second", "~>~~}" }, get_buf())
    assert.are.same({ 4, 2 }, vim.api.nvim_win_get_cursor(0))
  end)
end)

describe("highlighting", function()
  it("places extmarks for annotations", function()
    set_buf({ "one {++added++} word and {>>a note<<}" })
    cm.refresh(0)
    local marks = vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("criticmarkup"), 0, -1, {})
    assert.are.equal(6, #marks) -- two annotations x (open + content + close)
  end)

  it("resets inherited attributes over the replacement of a substitution", function()
    set_buf({ "the {~~bird~>condor~~} flew" })
    cm.refresh(0)
    local marks = vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("criticmarkup"), 0, -1, {
      details = true,
    })
    local reset
    for _, mark in ipairs(marks) do
      if mark[4].hl_group == "CriticIgnore" then
        reset = mark
      end
    end
    assert.is_not_nil(reset)
    -- From "~>" through the closing "~~}", and below the marks that colour it.
    assert.are.same({ 11, 21 }, { reset[3], reset[4].end_col - 1 })
    assert.is_true(reset[4].priority < 110)
    assert.is_true(vim.api.nvim_get_hl(0, { name = "CriticIgnore" }).nocombine)
  end)
end)

describe("paragraph blocks", function()
  after_each(function()
    cm.setup({ paragraph_blocks = false })
  end)

  it("is disabled by default", function()
    cm.setup({ paragraph_blocks = false })
    set_buf({ "[s: draft] Text" })
    cm.refresh(0)
    assert.are.equal(0, #paragraph_marks())
  end)

  it("conceals adjacent supported blocks at a paragraph start", function()
    cm.setup({ paragraph_blocks = true })
    set_buf({ "  [s:draft][s*:review] Text" })
    cm.refresh(0)

    local marks = paragraph_marks()
    assert.are.equal(1, #marks)
    assert.are.same({ 0, 2, 22 }, { marks[1][2], marks[1][3], marks[1][4].end_col })
    assert.are.equal("", marks[1][4].conceal)

    require("criticmarkup.paragraph_blocks").update(0, true)
    marks = paragraph_marks()
    assert.are.equal(20, #marks)
    assert.are.equal("[s:draft][s*:review]", revealed_text(marks, 0))
  end)

  it("reveals blocks only for the paragraph being edited", function()
    cm.setup({ paragraph_blocks = true })
    set_buf({
      "[s: first] First line",
      "continued here",
      "",
      "[s*: second] Other paragraph",
    })
    cm.attach(0)

    vim.api.nvim_win_set_cursor(0, { 2, 3 })
    vim.api.nvim_exec_autocmds("InsertEnter", { buffer = 0 })
    local marks = paragraph_marks()
    assert.are.equal(11, #marks)
    assert.are.equal("[s: first]", revealed_text(marks, 0))
    assert.are.same({ 3, "" }, { marks[11][2], marks[11][4].conceal })

    vim.api.nvim_win_set_cursor(0, { 4, 5 })
    vim.api.nvim_exec_autocmds("CursorMovedI", { buffer = 0 })
    marks = paragraph_marks()
    assert.are.equal(13, #marks)
    assert.are.same({ 0, "" }, { marks[1][2], marks[1][4].conceal })
    assert.are.equal("[s*: second]", revealed_text(marks, 3))

    vim.api.nvim_exec_autocmds("InsertLeave", { buffer = 0 })
    assert.are.equal(2, #paragraph_marks())
  end)

  it("leaves notes and non-leading blocks untouched", function()
    cm.setup({ paragraph_blocks = true })
    set_buf({
      "[note: ignore][s: not-leading] First",
      "",
      "[s: yes][note: ignore][s*: after-note] Second",
      "still has [note: inline] content",
      "",
      "Plain [s: inline] text",
    })
    cm.refresh(0)

    local marks = paragraph_marks()
    assert.are.equal(1, #marks)
    assert.are.same({ 2, 0, 8 }, { marks[1][2], marks[1][3], marks[1][4].end_col })
  end)
end)
