return {
  {"NvChad/nvim-colorizer.lua",
    config = function()
      require("colorizer").setup({
        user_default_options = {
          names = false,      -- 识别颜色名如 red/blue
          rgb_fn = true,
          hsl_fn = true,
        },
      })
    end
  },
}
