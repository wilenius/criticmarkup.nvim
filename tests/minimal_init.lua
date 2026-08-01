local plenary_dir = os.getenv("PLENARY_DIR") or "/tmp/plenary.nvim"
local is_not_a_directory = vim.fn.isdirectory(plenary_dir) == 0
if is_not_a_directory then
  vim.fn.system({"git", "clone", "https://github.com/nvim-lua/plenary.nvim", plenary_dir})
end

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

vim.cmd("runtime plugin/plenary.vim")
-- Tests run with --noplugin, so source our own plugin file to get the default
-- highlight groups.
vim.cmd("runtime plugin/criticmarkup.lua")
require("plenary.busted")
