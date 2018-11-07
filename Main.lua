require "RC522"

require "Login1"

--edit
ID = nil
station_cfg = {}
station_cfg.ssid = Login1.username
station_cfg.pwd = Login1.password
WifiConnectionRetryCount = 0
timeEnabled = 0
cardInserted = false
cardGone = false
cardGoneTimer = 0
cardGoneTimerLimit = 10
relayEnabled = false
permission = false
waitingForAnswer = false
ttl = 10
beepCount = 3
connected = false
reCheckConnectionTimer = 0
reCheckConnectionTimerLimit = 10
macAddress = wifi.sta.getmac()
header = Login1.header
-- End of config section

--default pin states
beeperPin = 0
gpio.write(beeperPin, gpio.LOW)

--beep(500, 1)

function beep(duration)
    --duration = duration *1000
    gpio.write(beeperPin, gpio.HIGH)
    tmr.create():alarm(duration, tmr.ALARM_SINGLE, function()
      gpio.write(beeperPin, gpio.LOW) 
    end)
end

function createConnection() --TODO: check if resets when failed
    print("Creating connection...")
    wifi.sta.disconnect()
    wifi.setmode(wifi.NULLMODE)
    tmr.delay(3000000)
    wifi.sta.config(station_cfg)
    wifi.setmode(wifi.STATION, false)
    wifi.sta.connect()
end

function checkConnection()
    print("Checking connection...")

    while wifi.sta.status() ~= wifi.STA_GOTIP do
        print("Connection status", wifi.sta.status())
        connected = false
        tmr.delay(3000000)
        createConnection() 
        tmr.delay(3000000)
    end 
    print("Connection status", wifi.sta.status())
end

--------------------------------------------------------
--  Converts a table of numbers into a HEX string
function appendHex(t)
  if t[4] ~= nil then
    strT = (t[4] * (256^3)) + (t[3] * (256^2)) + (t[2] * (256^1)) + (t[1] * (256^0)) 
    return string.format("%u", strT)
  end
  return ""
end

function sendRequestToServer()
    if ID ~= nil and ID ~= "" then
        if timeEnabled == 0 or timeEnabled >= ttl then
            timeEnabled = 0
            requestURL = "http://api.lan/api/v1/users/allowed/"..ID.."/"..macAddress
            print("Sending request to server")
            waitingForAnswer = true
            http.get(requestURL, "Authorization: Basic "..header.."\r\n", function(code, data)
                print("Got answer from server")
                if data ~= nil then
                    dataDecoded = cjson.decode(data)
                    for k,v in pairs(dataDecoded) do 
                        if k == "status" then permission = v end
                        if k == "ttl" then ttl = v end            
                    end
                    print(permission, " ", ttl)
                else
                    print("No data received from server")
                end
                waitingForAnswer = false
                timeEnabled = 1
            end)
         end   
    end
end

function checkPermissionFromServer()
    --check for permission and enable relay
    if permission == true and waitingForAnswer == false then
        timeEnabled = timeEnabled + 1
        print("Time enabled: ", timeEnabled)
        relayEnabled = true
    end
   
    --disable relay
    if permission == false then
        timeEnabled = 0
        relayEnabled = false
    end
end

function getID()
    oldID = ID
    ID = RC522.get_ID() 
    if ID == nil or ID == "" then
        if oldID ~= ID then 
            cardGone = true 
            print("Card gone!!!")
        end
    else
        cardGone = false
        cardGoneTimer = 0
        ID = appendHex(ID)
        print("ID: ", ID)
    end

    if cardGone == true then 
        cardGoneTimer = cardGoneTimer + 1
        if cardGoneTimer < beepCount + 1 then beep(500) end
    end
    if cardGoneTimer >= cardGoneTimerLimit then 
        cardGone = false 
        permission = false
    end  
end

function setRelay()
    if permission == true then
        print("Relay Enabled")
        gpio.write(1, gpio.HIGH)
    else
        print("Relay Disabled")
        gpio.write(1, gpio.LOW)
    end
end

function mainLoop()
    --check connection
    reCheckConnectionTimer = reCheckConnectionTimer + 1 
    if reCheckConnectionTimer >= reCheckConnectionTimerLimit then
        reCheckConnectionTimer = 0
        checkConnection() 
    end
    --print("waitingForAnswer ", waitingForAnswer)
    getID()

    --send and check request from server
    if waitingForAnswer == false then
        sendRequestToServer()
    end
    checkPermissionFromServer()
      
    setRelay()
end
    

createConnection()

tmr.alarm(0, 1000, tmr.ALARM_AUTO, function()
   mainLoop()
end)
