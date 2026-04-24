vim.g.mapleader = " "

local base = vim.fn.expand("~/.config/nvim")
vim.opt.rtp:prepend(base)
vim.opt.rtp:append(base .. "/after")
package.path = base .. "/lua/?.lua;" .. base .. "/lua/?/init.lua;" .. package.path

dofile(base .. "/lua/init.lua").setup({
  lazy = {
    extra_specs = {
      { import = "profile-plugins" },
    },
  }
})

vim.cmd("filetype plugin indent on")
vim.cmd("syntax on")
vim.cmd("colorscheme gruvbox")
