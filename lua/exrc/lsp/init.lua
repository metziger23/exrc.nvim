local M = {}

local loader = require('exrc.loader')
local log = require('exrc.log')
local utils = require('exrc.utils')
local Restart = require('exrc.lsp.restart')

--- Handler called in on_new_config hook that should update config in-place.
--- Called only after root_dir/client_name matching.
---@alias exrc.lsp.OnNewConfig fun(config: table, root_dir: string)

--- exrc_path -> client_name -> handler
---@type table<string, table<string, exrc.lsp.OnNewConfig>>
M.handlers = {}

--- lspconfig on_new_config hook that will call all registered handlers
function M.on_new_config(config, root_dir)
    ---@type { exrc_dir: string, handler: exrc.lsp.OnNewConfig }[]
    local matching = {}

    for exrc_path, handlers in pairs(M.handlers) do
        local exrc_dir = vim.fs.dirname(exrc_path)
        if utils.dir_matches(exrc_dir, root_dir) then
            for client_name, handler in pairs(handlers) do
                if config.name == client_name then
                    table.insert(matching, {
                        handler = handler,
                        exrc_dir = exrc_dir,
                        client_name = client_name,
                    })
                end
            end
        end
    end

    -- sort by longest exrc_dir first
    table.sort(matching, function(a, b)
        return #utils.clean_path(a.exrc_dir) > #utils.clean_path(b.exrc_dir)
    end)

    if #matching > 0 then
        local match = matching[1]
        match.handler(config, root_dir)
        log.debug(
            'exrc.lsp.on_new_config: applied for %s out of %d candidates from dir "%s"',
            config.name,
            #matching,
            match.exrc_dir
        )
    end
end


--- Call this as a method of exrc.Context to get correct exrc_path
---@param exrc_path string
---@param handlers table<string, exrc.lsp.OnNewConfig> maps client_name to handler (after root_dir/client matching)
function M.setup(exrc_path, handlers)
    assert(require('lspconfig'), 'lspconfig needs to be installed')

    local first = not M.handlers[exrc_path]
    local exrc_dir = vim.fs.dirname(exrc_path)
    log.debug(
        'exrc.lsp.setup(%s): %d handlers for dir: "%s"',
        first and 'first' or 'reload',
        #vim.tbl_keys(handlers),
        exrc_dir
    )

    M.handlers[exrc_path] = handlers

    -- restart all matching clients that are already running
    Restart:new(exrc_path, vim.tbl_keys(M.handlers[exrc_path])):add()

    loader.add_on_unload(exrc_path, function()
        local restart = Restart:new(exrc_path, vim.tbl_keys(M.handlers[exrc_path]))
        M.handlers[exrc_path] = nil
        restart:add()
    end)
end

return M
