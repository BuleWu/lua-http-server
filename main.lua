local socket = require("socket")
local server = assert(socket.bind("*", 8020))

local sessions = {}
local routes = {GET = {}, POST = {}, PUT = {}, DELETE = {}}
local middleware = {}
local mime_types = {
    html = "text/html",
    css = "text/css",
    js = "application/javascript",
    json = "application/json",
    png = "image/png",
    jpg = "image/jpeg",
    gif = "image/gif",
    txt = "text/plain",
    pdf = "application/pdf"
}

local function log(level, message)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    print(string.format("[%s] %s: %s", timestamp, level, message))
end

local function generateSessionId()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local id = ""
    math.randomseed(os.time() + socket.gettime() * 1000000)
    for i = 1, 32 do
        local idx = math.random(1, #chars)
        id = id .. chars:sub(idx, idx)
    end
    return id
end

local function parseQueryString(query)
    local params = {}
    if not query then return params end
    
    for key, value in query:gmatch("([^&=]+)=([^&=]*)") do
        params[key] = value:gsub("+", " "):gsub("%%(%x%x)", function(hex)
            return string.char(tonumber(hex, 16))
        end)
    end
    return params
end

local function parseCookies(cookie_header)
    local cookies = {}
    if not cookie_header then return cookies end
    
    for pair in cookie_header:gmatch("[^;]+") do
        local key, value = pair:match("^%s*(.-)%s*=%s*(.-)%s*$")
        if key and value then
            cookies[key] = value
        end
    end
    return cookies
end

local function readFile(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return content
end

local function getMimeType(filename)
    local ext = filename:match("%.([^%.]+)$")
    return mime_types[ext] or "application/octet-stream"
end

local function renderTemplate(template, context)
    return template:gsub("{{%s*(.-)%s*}}", function(key)
        return tostring(context[key] or "")
    end)
end

local function parseFormData(body)
    local data = {}
    for key, value in body:gmatch("([^&=]+)=([^&=]*)") do
        data[key] = value:gsub("+", " "):gsub("%%(%x%x)", function(hex)
            return string.char(tonumber(hex, 16))
        end)
    end
    return data
end

local function buildResponse(status, headers, body)
    local status_texts = {
        [200] = "OK",
        [201] = "Created",
        [204] = "No Content",
        [301] = "Moved Permanently",
        [302] = "Found",
        [400] = "Bad Request",
        [401] = "Unauthorized",
        [404] = "Not Found",
        [500] = "Internal Server Error",
        [501] = "Not Implemented"
    }
    
    local response = string.format("HTTP/1.1 %d %s\r\n", status, status_texts[status] or "Unknown")
    
    headers = headers or {}
    if body then
        headers["Content-Length"] = #body
    end
    
    for key, value in pairs(headers) do
        response = response .. string.format("%s: %s\r\n", key, value)
    end
    
    response = response .. "\r\n"
    if body then
        response = response .. body
    end
    
    return response
end

local function addRoute(method, pattern, handler)
    routes[method] = routes[method] or {}
    table.insert(routes[method], {pattern = pattern, handler = handler})
end

local function matchRoute(method, path)
    local route_list = routes[method]
    if not route_list then return nil end
    
    for _, route in ipairs(route_list) do
        local captures = {path:match(route.pattern)}
        if #captures > 0 or path:match(route.pattern) == path then
            return route.handler, captures
        end
    end
    return nil
end

local function use(fn)
    table.insert(middleware, fn)
end

local function executeMiddleware(request, response)
    for _, mw in ipairs(middleware) do
        local result = mw(request, response)
        if result == false then
            return false
        end
    end
    return true
end

addRoute("GET", "^/$", function(req, res, params)
    local template = readFile("./index.html")
    if template then
        local rendered = renderTemplate(template, {
            title = "Home",
            user = req.session.username or "Guest"
        })
        return res:send(200, {["Content-Type"] = "text/html"}, rendered)
    end
    return res:send(404, {}, "404 Not Found")
end)

addRoute("GET", "^/about$", function(req, res)
    local content = readFile("./about.html")
    if content then
        return res:send(200, {["Content-Type"] = "text/html"}, content)
    end
    return res:send(404, {}, "404 Not Found")
end)

addRoute("GET", "^/api/session$", function(req, res)
    local response_data = string.format('{"sessionId":"%s","username":"%s"}', 
        req.session_id or "none", 
        req.session.username or "guest")
    return res:send(200, {["Content-Type"] = "application/json"}, response_data)
end)

addRoute("POST", "^/login$", function(req, res)
    local form_data = parseFormData(req.body)
    
    if form_data.username and form_data.password then
        req.session.username = form_data.username
        req.session.logged_in = true
        log("INFO", "User logged in: " .. form_data.username)
        return res:redirect("/")
    end
    
    return res:send(400, {}, "Invalid credentials")
end)

addRoute("POST", "^/logout$", function(req, res)
    req.session.username = nil
    req.session.logged_in = nil
    return res:redirect("/")
end)

addRoute("GET", "^/static/(.+)$", function(req, res, params)
    local filename = params[1]
    local filepath = "./static/" .. filename
    local content = readFile(filepath)
    
    if content then
        return res:send(200, {["Content-Type"] = getMimeType(filename)}, content)
    end
    return res:send(404, {}, "File not found")
end)

use(function(req, res)
    log("INFO", string.format("%s %s from %s", req.method, req.path, req.client_ip))
    return true
end)

use(function(req, res)
    local session_id = req.cookies.session_id
    
    if session_id and sessions[session_id] then
        req.session = sessions[session_id]
        req.session_id = session_id
    else
        session_id = generateSessionId()
        sessions[session_id] = {}
        req.session = sessions[session_id]
        req.session_id = session_id
        res.cookies = res.cookies or {}
        res.cookies.session_id = session_id
    end
    
    return true
end)

local function handleRequest(client)
    local client_ip = client:getpeername()
    local request_text = ""
    local line, err = client:receive()
    
    if err then
        log("ERROR", "Client error: " .. err)
        return
    end
    
    local method, full_path, http_version = line:match("^(%u+)%s+(%S+)%s+(HTTP/%d%.%d)")
    
    if not method or not full_path then
        client:send(buildResponse(400, {}, "Bad Request"))
        return
    end
    
    local path, query_string = full_path:match("^([^?]*)%??(.*)")
    path = path or full_path
    
    local headers = {}
    local content_length = 0
    
    while true do
        line, err = client:receive()
        if err or line == "" then break end
        
        request_text = request_text .. line .. "\n"
        local key, value = line:match("^(.-):%s*(.*)")
        
        if key then
            key = key:lower()
            headers[key] = value
            
            if key == "content-length" then
                content_length = tonumber(value) or 0
            end
        end
    end
    
    local body = ""
    if content_length > 0 then
        body = client:receive(content_length) or ""
    end
    
    local request = {
        method = method,
        path = path,
        full_path = full_path,
        query = parseQueryString(query_string),
        headers = headers,
        body = body,
        cookies = parseCookies(headers.cookie),
        client_ip = client_ip,
        session = {}
    }
    
    local response = {
        cookies = {},
        send = function(self, status, headers, body)
            headers = headers or {}
            
            for cookie_name, cookie_value in pairs(self.cookies) do
                local cookie_header = headers["Set-Cookie"] or ""
                if cookie_header ~= "" then cookie_header = cookie_header .. ", " end
                cookie_header = cookie_header .. string.format("%s=%s; Path=/; HttpOnly", cookie_name, cookie_value)
                headers["Set-Cookie"] = cookie_header
            end
            
            client:send(buildResponse(status, headers, body))
        end,
        redirect = function(self, location)
            self:send(302, {["Location"] = location}, "")
        end
    }
    
    if not executeMiddleware(request, response) then
        return
    end
    
    local handler, params = matchRoute(method, path)
    
    if handler then
        local success, err = pcall(handler, request, response, params)
        if not success then
            log("ERROR", "Handler error: " .. tostring(err))
            response:send(500, {}, "Internal Server Error")
        end
    else
        response:send(404, {}, "Not Found")
    end
end

log("INFO", "Server started on port 8020")

while true do
    local client = server:accept()
    client:settimeout(10)
    
    local success, err = pcall(handleRequest, client)
    
    if not success then
        log("ERROR", "Request handling failed: " .. tostring(err))
    end
    
    client:close()
end