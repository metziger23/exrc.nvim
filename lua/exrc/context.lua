local utils = require('exrc.utils')
local loader = require('exrc.loader')

---@class exrc.Context
---@field exrc_path string
---@field load_info exrc.LoadInfo[]
local Context = {}
Context.__index = Context

-- Expose everyting via Context
Context.lsp = require('exrc.lsp')
Context.loader = require('exrc.loader')
Context.utils = require('exrc.utils')
Context.clean_path = Context.utils.clean_path

---@class exrc.InitOpts
--TODO: destructor callback

---@param opts exrc.InitOpts
---@return exrc.Context
function Context:new(opts)
    local info = utils.get_load_info()
    if #info == 0 then
        error('Could not detect exrc information')
    end
    return setmetatable({
        load_info = info,
        exrc_path = info[1].path
    }, self)
end

-- Similar to vim.fs.find { upward = true }, but limit is based on number of directories up (not #matches)
---@param dir string
---@param name string
---@param max_up integer
---@param stop? string
local function fs_find_up(dir, name, max_up, stop)
    local paths = {}
    local i = 1
    while dir and i <= max_up do
        if dir == stop then
            break
        end
        local path = vim.fs.joinpath(dir, name)
        local stat = vim.uv.fs_stat(path)
        if stat and stat.type == 'file' then
            table.insert(paths, path)
        end
        dir = assert(vim.fs.dirname(dir))
    end
    return paths
end

---@class exrc.SourceUpOpts
---@field max_dirs? integer Max number of directories to search up
---@field stop? string Directory to stop search at, defaults to home dir
---@field quiet? boolean Do not warn when nothing was sourced
---@field source_max? integer Max number of exrc files to source, defaults to 1 (load only "closest")

--- Source exrc file from directories up
---@param opts exrc.SourceUpOpts
function Context:source_up(opts)
    opts = opts or {}

    local dir = assert(vim.fs.dirname(self.exrc_path))
    local found = fs_find_up(dir, loader.EXRC_NAME, opts.max_dirs or math.huge, opts.stop)

    if #found > 0 then
        local n = 0
        for _, path in ipairs(found) do
            loader.load(path)
            n = n + 1
            if n >= (opts.source_max or math.huge) then
                break
            end
        end
        utils.log.debug('source_up: loaded %d files', n)
    elseif not opts.quiet then
      utils.log.warn('source_up: no exrc files found at "%s"', dir)
    end
end

--- Configure lsp.on_new_config handlers for clients with matching root_dir
---@param handlers table<string, exrc.lsp.OnNewConfig> mapping of client_name to handler (after root_dir/client matching)
function Context:lsp_setup(handlers)
    self.lsp.setup(self.exrc_path, handlers)
end

return Context
