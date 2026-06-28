local pluginList = {}

local function add(mod)
  local ok, p = pcall(require, mod)
  if ok and p then
    vim.list_extend(pluginList, p)
  end
end

add("plugins.aerial")
add("plugins.blink")
add("plugins.bufferline")
add("plugins.colorizer")
add("plugins.nvim-tree")
add("plugins.tokyonight")
add("plugins.agentic")

return pluginList
