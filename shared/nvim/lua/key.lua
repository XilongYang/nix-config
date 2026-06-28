vim.keymap.set('n', '<C-s>', ':w<CR>', {silent = true})
vim.keymap.set('i', '<C-s>', '<ESC>:w<CR>a', {silent = true})

vim.keymap.set('v', '<C-c>', 'y', {silent = true})
vim.keymap.set('i', '<C-v>', '<ESC>p', {silent = true})

vim.keymap.set('n', '<C-h>', '<C-w>h', {silent = true})
vim.keymap.set('n', '<C-j>', '<C-w>j', {silent = true})
vim.keymap.set('n', '<C-k>', '<C-w>k', {silent = true})
vim.keymap.set('n', '<C-l>', '<C-w>l', {silent = true})

vim.keymap.set('n', '<leader>tt', ':NvimTreeToggle<CR>', {silent = true})

vim.keymap.set('n', '<leader>p', ':BufferLinePick<CR>', {silent = true})
vim.keymap.set('n', '<leader>P', ':BufferLinePickClose<CR>', {silent = true})

vim.keymap.set('n', '<leader>l', ':BufferLineCycleNext<CR>', {silent = true})
vim.keymap.set('n', '<leader>h', ':BufferLineCyclePrev<CR>', {silent = true})

vim.keymap.set('n', '<leader>bh', ':BufferLineMovePrev<CR>', { silent = true, desc = 'Move buffer left' })
vim.keymap.set('n', '<leader>bl', ':BufferLineMoveNext<CR>', { silent = true, desc = 'Move buffer right' })

vim.keymap.set('n', '<leader>bO', ':BufferLineCloseOthers<CR>', { silent = true, desc = 'Close other buffers' })
vim.keymap.set('n', '<leader>bH', ':BufferLineCloseLeft<CR>', { silent = true, desc = 'Close buffers to the left' })
vim.keymap.set('n', '<leader>bL', ':BufferLineCloseRight<CR>', { silent = true, desc = 'Close buffers to the right' })

vim.keymap.set("n", "<leader>aa", "<cmd>AerialToggle!<CR>")

vim.keymap.set("n", "<leader>et", vim.diagnostic.open_float, { silent = true })
vim.keymap.set("n", "<leader>ep", vim.diagnostic.goto_prev, { silent = true })
vim.keymap.set("n", "<leader>en", vim.diagnostic.goto_next, { silent = true })
vim.keymap.set("n", "<leader>eq", vim.diagnostic.setloclist, { silent = true })

-- y 走系统剪贴板
vim.keymap.set('n', 'y', '"+y', { noremap = true, silent = true })
vim.keymap.set('n', 'yy', '"+yy', { noremap = true, silent = true })
vim.keymap.set('v', 'y', '"+y', { noremap = true, silent = true })

-- 打开操作提示
vim.keymap.set("n", "<leader>H", function()
  require("cheatsheet").open()
end, { desc = "Open floating cheat sheet" })

