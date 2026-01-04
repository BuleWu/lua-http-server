local socket = require("socket")
local server = assert(socket.bind("*", 8020))
-- local ip, port = server:getsockname()

local function readFile(path)
    local file = io.open(path, "rb")
    if not file then return nil end

    local content = file:read("*a")
    file:close()
    return content
end

while true do
    local client = server:accept()
    client:settimeout(10)
    
    local request_text = ""
    local line, err = client:receive()

    
    if not err then
        local method, route = line:match("^(%u+)%s+(%S+)")

        if method and route then           
            while not err do
                request_text = request_text .. line .. "\n"
                if line == "" then break end
                line, err = client:receive()
            end

            if method == "GET" then
                local filename = route
                if filename == "/" then
                  filename = "/index.html"
                -- elseif filename == "/about" then
                --     local response = "HTTP/1.1 200 OK\r\n\r\nThis is the about page"
                --     client:send(response)
                -- else
                --     local response = "HTTP/1.1 200 OK\r\n\r\nThis works!"
                --     client:send(response)
                -- end 
                end

                local filepath = "." .. filename
                local file_content = readFile(filepath)

                if file_content then
                    local response = "HTTP/1.1 200 OK\r\n" ..
                    "Content-Type: text/html\r\n" .. 
                    "Content-Length: " .. #file_content .. "\r\n" .. 
                    "\r\n" ..
                    file_content

                    client:send(response)
                else
                    local body = "404 Not Found"
                    client:send("HTTP/1.1 404 Not Found\r\nContent-Length: ".. #body .. "\r\n\r\n" .. body)
                end
            elseif method == "POST" then
                client:send("HTTP/1.1 501 Not Implemented\r\n\r\n")
            else
                client:send("HTTP/1.1 501 Not Implemented\r\n\r\n")
            end

            print("Received request:\n" ..request_text)
        else
            local response = "HTTP/1.1 400 Bad Request\r\n\r\n"
            client:send(response)
        end
    else
        print("Client disonnected on error: " ..err)
    end

    client:close()
end