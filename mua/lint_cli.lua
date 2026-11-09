-- File handling for `mua lint`; the rules and the outline live in mua.lint. The lint reads the
-- source's layout to know what belongs to the file and what belongs to a block, so it asks the
-- formatter first rather than judging indentation the formatter would change.
local fmt = require 'mua.fmt'
local lint = require 'mua.lint'

local M = {}

local function usage_text(command)
    return ('usage: %s [--outline] [--] [FILE ... | -]\n'
        .. 'Reports a file that does not open by saying what it is for, a declaration at the file\'s own\n'
        .. 'level with no comment, and a comment that opens by naming the declaration it describes.\n'
        .. '--outline prints the file as its declarations and comments.\n'
        .. 'their comments. Format the source first: the rules read the layout.\n'):format(command)
end

local function read(path)
    local f, err = io.open(path, 'rb')
    if not f then error(err, 0) end
    local text, why = f:read('*a')
    f:close()
    if not text then error(why, 0) end
    return text
end

local function report(path, finding)
    if finding.kind == 'file' then
        if finding.detail == 'rule' then
            io.write(('%s:%d: the file opens with a rule of dashes; say what the file is for\n'):format(
                path, finding.line))
        else
            io.write(('%s:%d: the file opens with code; say what the file is for\n'):format(
                path, finding.line))
        end
    elseif finding.kind == 'undocumented' then
        io.write(('%s:%d: no comment says what `%s` is for\n'):format(path, finding.line,
            table.concat(finding.names, '`, `')))
    else
        io.write(('%s:%d: the comment opens by naming `%s`; say what it is for\n'):format(path,
            finding.line, finding.names[1]))
    end
end

function M.run(args, o)
    o = o or {}
    o.command = o.command or 'mua lint'
    local outline, paths, stop = false, {}, false
    local i = 1
    while i <= #args do
        local a = args[i]
        if not stop and a == '--' then stop = true
        elseif not stop and a == '--outline' then outline = true
        elseif not stop and (a == '--help' or a == '-h') then io.write(usage_text(o.command)); return 0
        elseif not stop and a:sub(1, 1) == '-' and a ~= '-' then
            io.stderr:write(o.command, ': unknown option ', a, '\n')
            return 2
        else paths[#paths + 1] = a end
        i = i + 1
    end
    if #paths == 0 then paths[1] = '-' end
    if outline and #paths > 1 and paths[1] == '-' then
        io.stderr:write(o.command, ': stdin cannot be combined with other inputs\n')
        return 2
    end

    local ok, status = pcall(function()
        local reported = false
        for _, path in ipairs(paths) do
            local source = path == '-' and io.read('*a') or read(path)
            if fmt.format(source, nil, path) ~= source then
                error(('%s: lint: format the source first (%s --write %s): the rules read the layout')
                    :format(path, o.command:gsub('lint$', 'fmt'), path), 0)
            end
            if outline then
                io.write(lint.outline(source, path))
            else
                for _, finding in ipairs(lint.findings(source, path)) do
                    report(path, finding)
                    reported = true
                end
            end
        end
        return reported and 1 or 0
    end)
    if not ok then io.stderr:write(tostring(status), '\n'); return 2 end
    return status
end

return M
