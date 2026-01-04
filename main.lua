local socket = require("socket")
local server = assert(socket.bind("*", 0))
local ip, port = server:getsockname()
print("Please telnet to localhost on port " .. port)

while true do
    local client = server:accept()
    client:settimeout(10)
    
    local request_text = ""
    local line, err = client:receive()

    while not err do 
        request_text = request_text .. line .. "\n"
        if line == "" then break end
        line, err = client:receive()
    end    

    print("Received request:\n" ..request_text)

    local response = "HTTP/1.1 200 OK\r\n\r\nThis works!"
    client:send(response)
    client:close()
end