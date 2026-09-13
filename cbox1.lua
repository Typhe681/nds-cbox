---@diagnostic disable: undefined-global
local ROOM_INDEX = 1

local ROOM = ctx:GetEnv('ROOM', '')
local TAG  = ctx:GetEnv('TAG', '')
local USER = ctx:GetEnv('USER', '')
local KEY  = ctx:GetEnv('KEY', '')
local VER  = ctx:GetEnv('VER', '1063')
local PFP  = ctx:GetEnv('PFP',  '')
local LINK = ctx:GetEnv('LINK', '')

local BASE  = 'https://www3.cbox.ws/box/?boxid=' .. ROOM .. '&boxtag=' .. TAG
local WIDTH = 31
local RESET = '\x1b[39m'

local PALETTE = {
    '\x1b[91m','\x1b[92m','\x1b[93m','\x1b[94m','\x1b[95m','\x1b[96m',
    '\x1b[31m','\x1b[32m','\x1b[33m','\x1b[34m','\x1b[35m','\x1b[36m',
}

local lastId      = 0
local printedUpTo = 0
local frameCount  = 0
local pollActive  = false
local pollDone    = false
local pollResult  = nil

local function fileExists(path)
    local f = io.open(path, 'r')
    if f then f:close(); return true end
    return false
end

local function switchRoom(delta)
    local total = 0
    while fileExists('cbox' .. (total + 1) .. '.lua') do
        total = total + 1
    end
    if total <= 1 then return end
    local target = ((ROOM_INDEX - 1 + delta) % total + total) % total + 1
    if target == ROOM_INDEX then return end
    dofile('cbox' .. target .. '.lua')
end

local function colorFor(name)
    local h = 5381
    for i = 1, #name do h = (h * 33 + name:byte(i)) % 2147483647 end
    return PALETTE[(h % #PALETTE) + 1]
end

local function wrap(text, width)
    local out = {}
    for line in text:gmatch('[^\n]+') do
        while #line > width do
            local cut = width
            local space = line:sub(1, width):match('.*() ')
            if space and space > 1 then cut = space - 1 end
            table.insert(out, line:sub(1, cut))
            line = line:sub(cut + 1):gsub('^%s+', '')
        end
        table.insert(out, line)
    end
    if #out == 0 then table.insert(out, '') end
    return out
end

local function clean(s)
    if not s then return '' end
    s = s:gsub('<img[^>]*>',              '[image]')
    s = s:gsub('<audio[^>]*>.-</audio>',  '[audio]')
    s = s:gsub('<audio[^>]*/>',           '[audio]')
    s = s:gsub('<video[^>]*>.-</video>',  '[video]')
    s = s:gsub('<video[^>]*/>',           '[video]')
    s = s:gsub('<a[^>]*>(.-)</a>', '%1')
    s = s:gsub('<br%s*/?>', '\n')
    local prev
    repeat prev = s; s = s:gsub('<[^>]*>', '') until s == prev
    s = s:gsub('%s+[%w_%-]+%s*=%s*"[^"]*"', '')
    s = s:gsub("%s+[%w_%-]+%s*=%s*'[^']*'", '')
    s = s:gsub('="[^"]*"', '')
    s = s:gsub("='[^']*'", '')
    s = s:gsub('https?://[%w%._%-/%%?=&:#@!~+%%]+', '')
    s = s:gsub('www%.[%w%._%-/%%?=&:#@!~+%%]+', '')
    s = s:gsub('&nbsp;', ' ')
    s = s:gsub('&amp;', '&')
    s = s:gsub('&lt;', '<')
    s = s:gsub('&gt;', '>')
    s = s:gsub('&quot;', '"')
    s = s:gsub('&#0?39;', "'")
    s = s:gsub('%s+', ' ')
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    return s
end

local function urlenc(s)
    return (s:gsub('([^%w%-%._~])', function(c)
        return string.format('%%%02X', c:byte())
    end))
end

local function fetchSync(url, opts)
    local done, result = false, nil
    local started, msg = fetch(url, opts or {}, function(code, body, err)
        result = { code = code, body = body, err = err }
        done = true
    end)
    if not started then return nil, msg end
    while libnds.pmMainLoop() and not done do
        libnds.threadYield()
    end
    return result
end

local function printMessage(name, text)
    print(colorFor(name) .. name .. RESET .. ':')
    for _, w in ipairs(wrap(text, WIDTH - 2)) do
        print('  ' .. w)
    end
end

local function extractNewMessages(body)
    local msgs = {}
    local i = 0
    for ln in body:sub(2):gmatch('[^\n]+') do
        i = i + 1
        if i > 1 then
            local id, name, msg = ln:match(
                '^([^\t]*)\t[^\t]*\t[^\t]*\t([^\t]*)\t[^\t]*\t[^\t]*\t([^\t]*)'
            )
            if id and msg and name and #name > 0 then
                local rawBody = msg:match('<div class="body"[^>]*>(.-)</div>')
                    or msg:match("<div class='body'[^>]*>(.-)</div>")
                    or msg:match('<div[^>]-class="body"[^>]*>(.-)</div>')
                    or msg
                local rawName = name:match('<div class="nme"[^>]*>(.-)</div>')
                    or name:match("<div class='nme'[^>]*>(.-)</div>")
                    or msg:match('<div class="nme"[^>]*>(.-)</div>')
                    or msg:match("<div class='nme'[^>]*>(.-)</div>")
                    or name
                table.insert(msgs, {
                    id   = tonumber(id) or 0,
                    name = clean(rawName),
                    body = clean(rawBody),
                })
            end
        end
    end

    table.sort(msgs, function(a, b) return a.id < b.id end)

    local fresh = {}
    for _, m in ipairs(msgs) do
        if m.id > lastId then lastId = m.id end
        if m.id > printedUpTo and m.body ~= '' and m.name ~= '' then
            printedUpTo = m.id
            table.insert(fresh, m)
        end
    end
    return fresh
end

local function startPoll()
    if pollActive then return end
    pollActive = true
    pollDone = false
    pollResult = nil
    local started = fetch(BASE .. '&sec=ar&_v=' .. VER .. '&p=' .. lastId, {},
        function(code, body, err)
            pollResult = { code = code, body = body, err = err }
            pollDone = true
        end)
    if not started then pollActive = false end
end

local function post(text)
    if KEY == '' then print('[post error] no KEY set'); return end
    local body = 'aj=' .. VER
        .. '&lp=' .. tostring(lastId)
        .. '&pst=' .. urlenc(text)
        .. '&fp=0'
        .. '&lid=' .. tostring(math.random(1, 99999))
        .. '&nme=' .. urlenc(USER)
        .. '&key=' .. urlenc(KEY)
        .. '&pic=' .. urlenc(PFP)
        .. '&eml=' .. urlenc(LINK)
    local r = fetchSync(BASE .. '&sec=submit&_v=' .. VER, {
        method = 'POST',
        headers = { ['Content-Type'] = 'application/x-www-form-urlencoded' },
        body = body,
    })
    if r and r.body and r.body:sub(1, 1) == '0' then
        print('[post error] ' .. r.body:sub(2))
    end
end

pcall(math.randomseed, os.time and os.time() or 1)

print('connected to pseuchat')

do
    local r = fetchSync(BASE .. '&sec=ar&_v=' .. VER .. '&p=0')
    if r and r.body and #r.body > 0 and r.body:sub(1, 1) ~= '0' then
        local msgs = extractNewMessages(r.body)
        local n = #msgs
        local start = math.max(1, n - 9)
        for i = start, n do
            printMessage(msgs[i].name, msgs[i].body)
        end
    else
        local r2 = fetchSync(BASE)
        if r2 and r2.body then
            local lpid = r2.body:match('lpid:(%d+)')
            if lpid then
                lastId      = tonumber(lpid) or 0
                printedUpTo = lastId - 1
            end
        end
    end
end

local prompt = CliPrompt.new('> ')
prompt:printFullPrompt(false)
prompt:prepareForNextLine()

while libnds.pmMainLoop() do
    libnds.threadYield()
    libnds.scanKeys()
    local down = libnds.keysDown()
    local KEY_L, KEY_R = 512, 256
    if down & KEY_L ~= 0 then switchRoom(-1) end
    if down & KEY_R ~= 0 then switchRoom(1) end
    if not ctx.shell.focused then goto continue end

    prompt:update()

    local idle = (#prompt.input == 0) and (not prompt.enterPressed)
    if idle and not pollActive then
        frameCount = frameCount + 1
        if frameCount >= 10000 then
            frameCount = 0
            startPoll()
        end
    elseif #prompt.input > 0 then
        frameCount = 0
    end

    if pollDone then
        pollDone = false
        pollActive = false
        local r = pollResult
        pollResult = nil
        if r and r.body and #r.body > 0 and r.body:sub(1, 1) ~= '0' then
            local fresh = extractNewMessages(r.body)
            if #fresh > 0 then
                io.write('\r\x1b[2K')
                for _, m in ipairs(fresh) do printMessage(m.name, m.body) end
                prompt:printFullPrompt(true)
            end
        end
        prompt:printFullPrompt(true)
    end

    if prompt.enterPressed then
        local msg = prompt.input
        if msg and #msg > 0 then
            if pollActive then
                pollActive = false
                pollDone = false
                pollResult = nil
            end
            post(msg)
        end
        prompt:prepareForNextLine()
        io.write('\x1b[A\r\x1b[0K')
        prompt:printFullPrompt(false)
    end

    if prompt.foldPressed then
        print('bye!')
        break
    end

    ::continue::
end
