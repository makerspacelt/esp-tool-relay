require "RC522"

ID = nil
station_cfg = {}
station_cfg.ssid = "makerspace.lt"
station_cfg.pwd = ""
failedRetryCount = 0
timeEnabled = 0
cardInserted = false
cardGone = false
removedCardTimer = 0
removedCardTimerLimit = 10
relayEnabled = false
permission = false
waitingForAnswer = false
ttl = 10
connected = false
reCheckConnectionTimer = 0
reCheckConnectionTimerLimit = 300
macAddress = wifi.sta.getmac()
header = ""

function createConnection() --TODO: check if resets when failed
    print("Creating connection...")
    wifi.sta.disconnect()
    wifi.setmode(wifi.NULLMODE)
    wifi.sta.config(station_cfg)
    wifi.setmode(wifi.STATION)
    wifi.sta.connect()
end

function checkConnection()
    print("Connection status", wifi.sta.status())
    if wifi.sta.status() == wifi.STA_GOTIP then --if connected
        print("connected")
        connected = true
        failedRetryCount = 0
        return
    else                                        --if not connected
        print("No connection... Retrying")
        connected = false
        tmr.delay(5000000)
        failedRetryCount = failedRetryCount + 1

        if failedRetryCount == 5 then
            failedRetryCount = 0
            createConnection()    
        else
            checkConnection()
        end
    end    
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

function mainLoop()
    --check connection
    if connected == false then
        tmr.interval(0, 5000)
        checkConnection()
        return
    end

    --re-check connection
    reCheckConnectionTimer = reCheckConnectionTimer + 1
    if reCheckConnectionTimer >= reCheckConnectionTimerLimit then
        checkConnection()
        reCheckConnectionTimer = 0
        if connected == false then reCheckConnectionTimerLimit = 10 else reCheckConnectionTimerLimit = 30 end
    end    
    print("reCheckConnectionTimer ", reCheckConnectionTimer)
    
    
    tmr.interval(0, 1000)

    --get ID
    oldID = ID
    ID = RC522.get_ID() 
    if ID == nil or ID == "" then
        timeEnabled = 0
        requestGot = false
        permission = false
        cardInserted = false 
        if oldID ~= ID then 
            print("oldID ", oldID, "ID ", ID)
            cardGone = true 
            print("card gone")
        end
    else
        cardInserted = true
        cardGone = false
        removedCardTimer = 0
        ID = appendHex(ID)
    end

    --beep if removedCardTimer running
    if cardGone == true then
        removedCardTimer = removedCardTimer + 1
        if removedCardTimer >= removedCardTimerLimit then cardGone = false end
        print("BEEP!")
    end    
    
    --check for permission and enable relay
    if permission == true and waitingForAnswer == false and cardInserted == true then
        timeEnabled = timeEnabled + 1
        print("Time enabled: ", timeEnabled)
        relayEnabled = true
    end

    --disable relay
    if permission == false and removedCardTimer >= removedCardTimerLimit then
        relayEnabled = false
    end

    --send request and assign values
    if timeEnabled == 0 or timeEnabled >= ttl then
        if waitingForAnswer == false and cardInserted == true then
            waitingForAnswer = true
            timeEnabled = 0
            requestURL = "http://api.lan/api/v1/users/allowed/"..ID.."/"..macAddress
            http.get(requestURL, "Authorization: Basic "..header.."\r\n", function(code, data)
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
            end)
        end
     end

    --enable relay
    if relayEnabled == true then
        print("Relay Enabled")
        gpio.write(1, gpio.HIGH)
    else
        print("Relay Disabled")
        gpio.write(1, gpio.LOW)
    end
    
    --TODO: move passwords to cfg
end
    


createConnection()

tmr.alarm(0, 5000, tmr.ALARM_AUTO, function()
   mainLoop()
end)
