local socket = require("socket")
local server = assert(socket.bind("*", 8020))
local ip, port = server:getsockname()
print("Please telnet to localhost on port " .. port)

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
                if route == "/" then
                    local response = "HTTP/1.1 200 OK\r\n\r\nThis is the home page"
                    client:send(response)
                elseif route == "/about" then
                    local response = "HTTP/1.1 200 OK\r\n\r\nThis is the about page"
                    client:send(response)
                else
                    local response = "HTTP/1.1 200 OK\r\n\r\nThis works!"
                    client:send(response)
                end 
                
            else
                local response = "HTTP/1.1 200 OK\r\n\r\nThis works!"
                client:send(response)
            end
            -- elseif method == "POST" then
            -- end

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