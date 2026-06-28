local M = {}

-- ============================================================================
-- Flat data (WYSIWYG style)
-- ============================================================================

local DATA = {
  { "header", "Neovim Cheat Sheet" },

  { "section", "LEADER" },
  { "item", "<Space>", "Leader key" },

  { "section", "LSP" },
  { "item", "gd", "Definition", "LSP only" },
  { "item", "gD", "Declaration", "LSP only" },
  { "item", "gr", "References", "LSP only" },
  { "item", "gi", "Implementation", "LSP only" },
  { "item", "K", "Hover", "LSP only" },
  { "item", "<leader>rn", "Rename", "LSP only" },
  { "item", "<leader>ca", "Code action", "normal/visual" },
  { "item", "<leader>f", "Format buffer" },

  { "section", "AI / Agentic + CodeX" },
  { "item", "<leader>at", "Toggle Agentic panel" },
  { "item", "<leader>an", "New Agentic session" },
  { "item", "<leader>af", "Add current file to session" },

  { "section", "AI (VISUAL)" },
  { "item", "<leader>as", "Add selection to session", "select first" },

  { "section", "COMPLETION" },
  { "item", "<Tab>", "Accept / jump" },
  { "item", "<S-Tab>", "Reverse jump" },
  { "item", "<Up>", "Prev item" },
  { "item", "<Down>", "Next item" },
  { "item", "<C-j>", "Next (menu)" },
  { "item", "<C-k>", "Prev (menu)" },
  { "item", "<C-b>", "Scroll up" },
  { "item", "<C-f>", "Scroll down" },
  { "item", "<C-y>", "Toggle signature" },

  { "section", "AERIAL" },
  { "item", "<leader>aa", "Toggle outline" },
  { "item", "{", "Previous symbol", "Aerial only" },
  { "item", "}", "Next symbol", "Aerial only" },

  { "section", "DIAGNOSTICS" },
  { "item", "<leader>et", "Show float" },
  { "item", "<leader>ep", "Previous diagnostic" },
  { "item", "<leader>en", "Next diagnostic" },
  { "item", "<leader>eq", "To loclist" },

  { "section", "NVIM TREE" },
  { "item", "<leader>tt", "Toggle NvimTree" },
  { "item", "<CR>", "Open file / enter dir" },
  { "item", "o", "Open file (same as <CR>)" },
  { "item", "v", "Open in vertical split" },
  { "item", "h", "Close dir / go parent" },
  { "item", "l", "Open dir / file" },
  { "item", "a", "Create file / dir" },
  { "item", "d", "Delete file / dir" },
  { "item", "r", "Rename file" },
  { "item", "R", "Refresh tree" },
  { "item", "H", "Toggle hidden files" },
  { "item", "y", "Copy filename" },
  { "item", "c", "Copy file" },
  { "item", "x", "Cut file" },
  { "item", "p", "Paste (after copy)" },

  { "section", "GENERAL" },
  { "item", "<C-s>", "Save file", "normal / insert" },
  { "item", "<C-c>", "Copy selection", "visual" },
  { "item", "<C-v>", "Paste", "insert" },

  { "section", "BUFFERS (CUSTOM)" },
  { "item", "<leader>h", "Previous buffer" },
  { "item", "<leader>l", "Next buffer" },
  { "item", "<leader>p", "Pick buffer" },
  { "item", "<leader>P", "Pick & close buffer" },
  { "item", "<leader>bO", "Close all other buffer" },
  { "item", "<leader>bH", "Close all left buffer" },
  { "item", "<leader>bL", "Close all right buffer" },

  { "section", "BUFFERS (BUILT-IN)" },
  { "item", ":ls", "List buffers" },
  { "item", ":b <num>", "Go to buffer" },
  { "item", ":bn", "Next buffer" },
  { "item", ":bp", "Prev buffer" },
  { "item", ":bd", "Delete buffer" },
  { "item", ":bd!", "Force delete" },
  { "item", ":e #", "Alternate file" },

  { "section", "WINDOWS (CUSTOM)" },
  { "item", "<C-h>", "Left window" },
  { "item", "<C-j>", "Lower window" },
  { "item", "<C-k>", "Upper window" },
  { "item", "<C-l>", "Right window" },

  { "section", "WINDOWS (BUILT-IN)" },
  { "item", "<C-w>h", "Left window" },
  { "item", "<C-w>j", "Lower window" },
  { "item", "<C-w>k", "Upper window" },
  { "item", "<C-w>l", "Right window" },
  { "item", "<C-w>w", "Cycle windows" },
  { "item", "<C-w>s", "Horizontal split" },
  { "item", "<C-w>v", "Vertical split" },
  { "item", "<C-w>c", "Close window" },
  { "item", "<C-w>o", "Close others" },
  { "item", "<C-w>=", "Equalize size" },

  { "section", "MACROS" },
  { "item", "qa ... q", "Record macro into register a" },
  { "item", "@a", "Replay macro a" },
  { "item", "@@", "Replay last macro" },
  { "item", "N@a", "Replay macro a N times" },
  { "item", ":reg / :reg a", "Inspect registers / macro content" },

  { "section", "MACRO NOTES" },
  { "note", "Best for repetitive edits across many similar lines" },
  { "note", "Record once, verify once, then replay with count" },
  { "note", "Prefer simple, deterministic cursor motions" },

  { "section", "NOTES" },
  { "note", "Leader is Space" },
  { "note", "LSP only works when attached" },
  { "note", "AI uses Agentic.nvim with codex-acp" },
  { "note", "Buffer = file, Window = viewport" },

  { "section", "OPEN" },
  { "item", "<leader>H", "Open this panel" },
}

-- ============================================================================
-- Render logic
-- ============================================================================

local function setup_hl()
  vim.api.nvim_set_hl(0, "CS_Header", { fg = "#cba6f7", bold = true })
  vim.api.nvim_set_hl(0, "CS_Title", { fg = "#89b4fa", bold = true })
  vim.api.nvim_set_hl(0, "CS_Key", { fg = "#f9e2af", bold = true })
  vim.api.nvim_set_hl(0, "CS_Note", { fg = "#a6adc8", italic = true })
  vim.api.nvim_set_hl(0, "CS_Sep", { fg = "#313244" })
end

local function build()
  local entries = {}

  for _, row in ipairs(DATA) do
    local t = row[1]

    if t == "header" then
      table.insert(entries, { "CS_Header", row[2] })
      table.insert(entries, { "CS_Sep", "===================" })

    elseif t == "section" then
      table.insert(entries, { nil, "" })
      table.insert(entries, { "CS_Title", row[2] })
      table.insert(entries, { "CS_Sep", string.rep("─", #row[2] + 4) })

    elseif t == "item" then
      local key, desc, note = row[2], row[3], row[4]
      local text = string.format("  %-18s %s", key, desc)
      if note then
        text = text .. "  [" .. note .. "]"
      end
      table.insert(entries, { "item", text })

    elseif t == "note" then
      table.insert(entries, { "CS_Note", "  - " .. row[2] })
    end
  end

  return entries
end

local function render(buf, entries)
  for i, e in ipairs(entries) do
    local l = i - 1
    local hl, text = e[1], e[2]

    if hl == "item" then
      local ks, ke = text:find("^%s+%S+")
      if ks then
        vim.api.nvim_buf_add_highlight(buf, -1, "CS_Key", l, ks - 1, ke)
      end

      local ns, ne = text:find("%s%b[]")
      if ns then
        vim.api.nvim_buf_add_highlight(buf, -1, "CS_Note", l, ns - 1, ne)
      end
    elseif hl then
      vim.api.nvim_buf_add_highlight(buf, -1, hl, l, 0, -1)
    end
  end
end

function M.open()
  setup_hl()
  local entries = build()

  local lines = {}
  for _, e in ipairs(entries) do
    table.insert(lines, e[2])
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local width = math.floor(vim.o.columns * 0.7)
  local height = math.floor((vim.o.lines - vim.o.cmdheight) * 0.8)

  local row = math.floor((vim.o.lines - height) / 2 - 1)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = "rounded",
    style = "minimal",
  })

  render(buf, entries)

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf })
end

return M
