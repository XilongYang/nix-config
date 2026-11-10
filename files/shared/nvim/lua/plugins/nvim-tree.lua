return {
  {"nvim-tree/nvim-tree.lua",
    config = function()
      require("nvim-tree").setup({
        on_attach = function(bufnr)
          local api = require("nvim-tree.api")

          local function opts(desc)
            return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
          end

          -- keep default mappings
          api.config.mappings.default_on_attach(bufnr)

          -- custom mappings
          vim.keymap.set("n", "h", api.node.open.horizontal, opts("Open horizontal split"))
          vim.keymap.set("n", "v", api.node.open.vertical, opts("Open vertical split"))

          -- descend the root one level, guided by the path of the node under the cursor
          local function change_root_down()
            local node = api.tree.get_node_under_cursor()
            if not node or not node.parent then
              return -- cursor is on the root node
            end

            -- walk up via parent to the direct child of the current root
            local target = node
            while target.parent.parent do
              target = target.parent
            end

            if vim.fn.isdirectory(target.absolute_path) == 0 then
              return -- that direct child is a file, nowhere to descend
            end

            api.tree.change_root_to_node(target)
            api.tree.find_file({ buf = node.absolute_path })
          end

          vim.keymap.set("n", "H", api.tree.change_root_to_parent, opts("Root: up"))
          vim.keymap.set("n", "L", change_root_down, opts("Root: down towards cursor"))
          vim.keymap.set("n", ".", api.filter.dotfiles.toggle, opts("Toggle Filter: Dotfiles"))
          vim.keymap.set("n", "!", api.node.run.cmd, opts("Run Command"))
        end,
      })
    end,
  },
}
