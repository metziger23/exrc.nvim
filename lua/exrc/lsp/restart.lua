local log = require('exrc.log')
local utils = require('exrc.utils')

-- LSP restart based on nvim-lspconfig's :LspRestart
---@class exrc.lsp.Restart
---@field exrc_path string
---@field client_names table<string, boolean>
local Restart = {}
Restart.__index = Restart

---@type exrc.lsp.Restart[]
Restart.queue = {}
---@type thread?
Restart.co = nil

---@param exrc_path string
---@param client_names string[]
---@return exrc.lsp.Restart
function Restart:new(exrc_path, client_names)
    return setmetatable({
        exrc_path = exrc_path,
        -- Restart only the clients for which we had handlers registered
        client_names = utils.list_to_set(client_names),
    }, self)
end

function Restart:add()
    table.insert(Restart.queue, self)
    Restart._lanuch_next()
end

function Restart._lanuch_next()
    if Restart.co and coroutine.status(Restart.co) == 'dead' then
        Restart.co = nil
    end
    if not Restart.co and next(Restart.queue) then
        Restart.co = coroutine.create(Restart._task)
        coroutine.resume(Restart.co, table.remove(Restart.queue, 1))
    end
end

---@return vim.lsp.Client[]
function Restart:_get_clients()
    local exrc_dir = vim.fs.dirname(self.exrc_path)
    local clients = {}
    for _, client in ipairs(vim.lsp.get_clients()) do
        if utils.dir_matches(exrc_dir, client.config.root_dir) and self.client_names[client.config.name] then
            table.insert(clients, client)
        end
    end
    return clients
end

function Restart:_run()
    local resume = utils.coroutine_resume()
    local sleep = function(timeout_ms)
        vim.defer_fn(resume, timeout_ms)
        coroutine.yield()
    end

    ---@type table<string, { client: vim.lsp.Client, buffers: integer[] }>
    local to_reattach = {}
    local n_clients = 0
    local n_buffers = 0

    for _, client in ipairs(self:_get_clients()) do
        client.stop()
        n_clients = n_clients + 1
        if vim.tbl_count(client.attached_buffers) > 0 then
            to_reattach[client.config.name] = {
                client = client,
                buffers = vim.tbl_keys(client.attached_buffers),
            }
            n_buffers = n_buffers + #to_reattach[client.config.name].buffers
        end
    end

    log.trace('Restart %d LSP clients (%d buffers) for exrc_path=%s', n_clients, n_buffers, self.exrc_path)

    sleep(500)

    --- { buf: { client_name: true } }
    ---@type table<integer, table<string, boolean>>
    local wait_for = {}

    while next(to_reattach) do
        for client_name, data in pairs(to_reattach) do
            if data.client.is_stopped() then
                -- launch this client for previous list of buffers
                for _, buf in ipairs(data.buffers) do
                    if vim.api.nvim_buf_is_valid(buf) then
                        require('lspconfig.configs')[client_name].launch(buf)
                        wait_for[buf] = wait_for[buf] or {}
                        wait_for[buf][client_name] = true
                    end
                end
                to_reattach[client_name] = nil
            end
        end
        sleep(100)
    end

    log.trace('Wait for %d LSP clients to attach to %d buffers', n_clients, n_buffers)

    -- Wait for clients on all buffers to start
    local max_iters = 20
    local i = 0
    while next(wait_for) and i < max_iters do
        i = i + 1
        for buf, wait_clients in pairs(wait_for) do
            for _, client in ipairs(vim.lsp.get_clients { bufnr = buf }) do
                if wait_clients[client.config.name] then
                    wait_clients[client.config.name] = nil
                end
            end
            if vim.tbl_count(wait_clients) == 0 then
                wait_for[buf] = nil
            end
        end
        sleep(100)
    end

    log.trace('LSP restart done for exrc_path=%s', self.exrc_path)
end

---@param other exrc.lsp.Restart
function Restart:eq(other)
    if not other or other.exrc_path ~= self.exrc_path then
        return false
    end
    return table.concat(self.client_names, ',') == table.concat(other.client_names, ',')
end

function Restart:_task()
    local resume = utils.coroutine_resume()

    -- HACK: prevent double restart due to things like immediate on_unload+load
    -- by waiting single loop step and then skipping this task if the same one is queued
    vim.schedule(resume)
    coroutine.yield()

    if not self:eq(self.queue[1]) then
        self:_run()
    end

    vim.schedule_wrap(Restart._lanuch_next)()
end

return Restart
