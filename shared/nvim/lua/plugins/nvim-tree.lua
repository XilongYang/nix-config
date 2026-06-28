return {
  {"nvim-tree/nvim-tree.lua",
    config = function()
      require("nvim-tree").setup({
        on_attach = function(bufnr)
          local api = require("nvim-tree.api")

          local function opts(desc)
            return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
          end

          -- 保留默认映射
          api.config.mappings.default_on_attach(bufnr)

          -- 自定义映射
          vim.keymap.set("n", "l", api.tree.change_root_to_node, opts("CD into directory"))
          vim.keymap.set("n", "h", api.tree.change_root_to_parent, opts("CD to parent"))
          vim.keymap.set("n", "v", api.node.open.vertical, opts("Open vertical split"))
        end,
      })
    end,
  },
}
