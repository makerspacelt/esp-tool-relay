require "RC522"
require "Login1"

--config
ID = nil
station_cfg = {}
station_cfg.ssid = Login1.username
station_cfg.pwd = Login1.password
WifiConnectionRetryCount = 0
timeEnabled = 0
cardInserted = false

cardGoneTimer = 0
cardGoneTimerLimit = 10

--relayEnabled = false
--permission = false
--waitingForAnswer = false
--waitingTimeoutCounter = 0

ttl = 10

reCheckConnectionTimer = 0
reCheckConnectionTimerLimit = 10
macAddress = wifi.sta.getmac()
header = Login1.header

--device states
	state_boot = 0
	state_idle = 1
	state_acquire = 2
	state_enabled = 3
	state_cardGone = 4
	state_newEntry = 5
state = state_boot 

--pins
	--D7 MOSI
	--D8 SDA
	--D5 SDK
	--D6 SOI
	--RST 3.3V
beeperPin = 1
RelayInPin = 0
powerLEDpin = 4
connectionLEDpin = 3 
cardLEDpin = 2
LEDblinkDuration = 500


--default pin states
gpio.mode(beeperPin, gpio.OUTPUT, gpio.FLOAT)
gpio.mode(RelayInPin, gpio.OUTPUT, gpio.FLOAT)
gpio.mode(powerLEDpin, gpio.OUTPUT)
gpio.mode(connectionLEDpin, gpio.OUTPUT)
gpio.mode(cardLEDpin, gpio.OUTPUT)
gpio.mode(cardLEDpin, gpio.OUTPUT)

gpio.write(beeperPin, gpio.LOW)
gpio.write(RelayInPin, gpio.LOW)
gpio.write(powerLEDpin, gpio.LOW)
gpio.write(connectionLEDpin, gpio.LOW)
gpio.write(cardLEDpin, gpio.LOW)



boo;

tmr.alarm(0, 1000, tmr.ALARM_AUTO, function()
   mainLoop()
end)

function boot()
	state = state_boot
	
	LED("power", "on")
	LED("server", "on")
	LED("card", "on")
	
	createConnection()

	tmr.delay(1000000)
	LED("server", "off")
	LED("card", "off")
	
	state = state_idle
end



function mainLoop()

	if state == state_idle then
		--check connection
		reCheckConnectionTimer = reCheckConnectionTimer + 1 
		if reCheckConnectionTimer >= reCheckConnectionTimerLimit then
			reCheckConnectionTimer = 0
			checkConnection()
		end
		
		checkCard()
	end	
		
	if state == state_acquire
		--send and check request from server
		if waitingForAnswer == false then
			sendRequestToServer()
		else
			waitingTimeoutCounter = waitingTimeoutCounter +1
		end
		if waitingTimeoutCounter > 8 then waitingForAnswer = false end
		checkPermissionFromServer()
	end
	
	if state == state_enabled
	    setRelay()
	end
	
	
	if state == state_cardGone then
		cardGoneTimer = cardGoneTimer + 1
		if cardGoneTimer < cardGoneTimerLimit + 1 then beep(500) end

		if cardGoneTimer >= cardGoneTimerLimit then state = 1 end  
	end
	
	if state == state_newEntry
	gone


     

end

function checkCard()
    oldID = ID
    ID = RC522.get_ID() 

    if ID == nil or ID == "" then
        if oldID ~= ID then 
            state = 4
        end
    else
        state = 2
        ID = appendHex(ID)
        print("ID: ", ID)
    end
end

function createConnection() --TODO: check if resets when failed
    print("Creating connection...")
    wifi.setmode(wifi.STATION, false)
    wifi.sta.config(station_cfg)
    checkConnection()
end

function checkConnection()
    print("Connection status", wifi.sta.status())
    if wifi.sta.status() ~= wifi.STA_GOTIP then 
        LED("server", "off") 
    else
        LED("server", "on")
    end    
end




function beep(duration)
    --duration = duration *1000
    gpio.write(beeperPin, gpio.HIGH)
    tmr.create(0):alarm(duration, tmr.ALARM_SINGLE, function()
      gpio.write(beeperPin, gpio.LOW) 
    end)
end

function setLED(led, state)
    local pin
    local LedID 
    if led == "power" then pin = powerLEDpin  LedID = 1 end
    if led == "server" then pin = connectionLEDpin  LedID = 2 end
    if led == "card" then pin = cardLEDpin  LedID = 3 end

    if state == "off" then tmr.unregister(LedID) gpio.write(pin, gpio.HIGH) end
    if state == "blink" then
        tmr.alarm(LedID, LEDblinkDuration, tmr.ALARM_AUTO, getTimerCallback(pin)) 
    end
    if state == "on" then tmr.unregister(LedID) gpio.write(pin, gpio.LOW) end
end

function getTimerCallback(tpin)
return function()
      if gpio.read(tpin) == 0 then 
        gpio.write(tpin, gpio.HIGH) 
      else 
        gpio.write(tpin, gpio.LOW) 
      end
    end
end


tmr.alarm(6, 100, tmr.ALARM_AUTO, function()
    pinState = gpio.read(connectionLEDpin)
    gpio.mode(connectionLEDpin, gpio.INPUT, gpio.PULLUP)
    --if gpio.read(connectionLEDpin) == 0 then print("pressed") end
    gpio.mode(connectionLEDpin, gpio.OUTPUT)
    gpio.write(connectionLEDpin, pinState)
end)



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
        LED("card", "blink")
        if timeEnabled == 0 or timeEnabled >= ttl then
            timeEnabled = 0
            requestURL = "http://192.168.1.72/api/v1/users/allowed/"..ID.."/"..macAddress
            print("Sending request to server")
            waitingForAnswer = true
            waitingTimeoutCounter = 0
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
        LED("card", "on")
        relayEnabled = true
    end
   
    --disable relay
    if permission == false then
        timeEnabled = 0
        if cardGone == true or waitingForAnswer == false then 
            LED("card", "off") 
        end
        relayEnabled = false
    end
end


function setRelay()
    if permission == true then
        print("Relay Enabled")
        gpio.write(RelayInPin, gpio.HIGH)
    else
        print("Relay Disabled")
        gpio.write(RelayInPin, gpio.LOW)
    end
end


