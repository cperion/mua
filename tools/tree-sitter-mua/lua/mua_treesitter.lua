-- GPL-3.0-or-later. See ../../../COPYING.
local M = {}

-- Uses Neovim's built-in Tree-sitter API, not nvim-treesitter's installer API.
local function runtime_dir()
  local source = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(source, ':p:h:h')
end

-- where `make tree-sitter` puts the parser library
function M.parser_path()
  local root = vim.fn.fnamemodify(runtime_dir(), ':h:h')
  return root .. '/build/tree-sitter-mua/mua.so'
end

-- Register the Mua language. Mua source is Lua source, so the filetype is opt-in:
--   setup({ extension = 'mua' })        files named *.mua are Mua (the default)
--   setup({ extension = false })        register the parser only; set the filetype yourself
-- A host language built on Mua (Nua) registers its own language over the same library with
-- M.add_language('nua', { extension = 'nua' }).
function M.setup(opts)
  opts = opts or {}
  local parser = opts.parser or M.parser_path()
  if vim.fn.filereadable(parser) ~= 1 then
    error('Mua parser not found: ' .. parser .. '; run make tree-sitter in the Mua repository')
  end
  M.parser = parser
  vim.opt.runtimepath:prepend(runtime_dir())
  vim.treesitter.language.add('mua', { path = parser })
  M.attach('mua', opts.extension == nil and 'mua' or opts.extension)
end

-- Highlight files of filetype `name` with the parser of `lang`, and (when `extension` is a
-- string) make *.extension files that filetype.
function M.attach(name, extension, lang)
  lang = lang or name
  if extension then vim.filetype.add({ extension = { [extension] = name } }) end
  local group = vim.api.nvim_create_augroup('MuaTreesitter_' .. name, { clear = true })
  local function start(buf)
    vim.treesitter.start(buf, lang)
    vim.bo[buf].commentstring = '-- %s'
  end
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = name,
    callback = function(event) start(event.buf) end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == name then start(buf) end
  end
end

-- Another language over the same parser library (a host's), with its own queries
function M.add_language(name, opts)
  opts = opts or {}
  vim.treesitter.language.add(name, { path = M.parser, symbol_name = 'mua' })
  M.attach(name, opts.extension, name)
end

return M
