if vim.g.loaded_criticmarkup then
  return
end
vim.g.loaded_criticmarkup = true

local group = vim.api.nvim_create_augroup("criticmarkup", { clear = true })

local function set_default_hl()
  local hl = vim.api.nvim_set_hl
  hl(0, "CriticAddition", { default = true, link = "DiffAdd" })
  hl(0, "CriticDeletion", { default = true, link = "DiffDelete" })
  hl(0, "CriticHighlight", { default = true, link = "DiffText" })
  hl(0, "CriticComment", { default = true, link = "Comment" })
  hl(0, "CriticMarker", { default = true, link = "Delimiter" })
end
set_default_hl()
vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_default_hl })

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  callback = function(ev)
    local cm = require("criticmarkup")
    if vim.tbl_contains(cm.config.filetypes, ev.match) then
      cm.attach(ev.buf)
    end
  end,
})

vim.api.nvim_create_user_command("CriticMarkup", function(opts)
  local cm = require("criticmarkup")
  local action = opts.fargs[1]
  if action ~= "accept" and action ~= "reject" then
    vim.notify("criticmarkup: use ':CriticMarkup accept' or ':CriticMarkup reject'", vim.log.levels.ERROR)
    return
  end
  if opts.range > 0 then
    cm[action .. "_range"](opts.line1, opts.line2)
  else
    cm[action]()
  end
end, {
  nargs = 1,
  range = true,
  complete = function()
    return { "accept", "reject" }
  end,
})
