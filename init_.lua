require "RC522"
require "Login1"

--wifi
ID = nil
station_cfg = {}
station_cfg.ssid = Login1.username
station_cfg.pwd = Login1.password
WifiConnectionRetryCount = 0
macAddress = wifi.sta.getmac()
header = Login1.header

timeEnabled = 0
cardGoneTimer = 0
cardGoneTimerLimit = 3
waitingForAnswer = false
waitingTimeoutCounter = 0
ttl = 10
ttlOverride = 10 --0 if disabled

silentBeep = true

--device states
	state_boot = 0
	state_noConnection = 1
	state_idle = 2
	state_acquire = 3
	state_enabled = 4
	state_cardGone = 5
	state_newEntry = 6
state = -1 

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


function boot()
	setState(state_boot)
	
	setLED("power", "on")
	setLED("server", "on")
	setLED("card", "on")
	
	createConnection()

	tmr.delay(1000000)
	setLED("server", "off")
	setLED("card", "off")
	
	setState(state_noConnection)
end

function mainLoop()
	if state == state_noConnection then 
		if checkConnection() == true then 
			setState(state_idle) 
		else
			print("--createConnection() --needs timer")
		end
	end
	
	if state == state_idle then
		setRelay(0)
		setLED("card", "off") 
	
		if checkConnection() == false then setState(state_noConnection) end
		
		setStateByCard(isCardIn())
	end	
		
	if state == state_acquire then
		timeEnabled = 0
		if waitingForAnswer == false then
			sendRequestToServer()
		else
			waitingTimeoutCounter = waitingTimeoutCounter +1
		end
		if waitingTimeoutCounter > 8 then waitingForAnswer = false end
		if checkConnection() == false then setState(state_noConnection) end
	end
	
	if state == state_enabled then
	    setRelay(1)
		setLED("card", "on")
		timeEnabled = timeEnabled + 1
		if checkConnection() == false then setState(state_cardGone) end
		
		cardState = isCardIn()
		if cardState == 1 then
			sendRequestToServer()
		elseif cardState == 2 then 
			setState(state_cardGone) 
		end
	end
		
	if state == state_cardGone then
		cardGoneTimer = cardGoneTimer + 1
		if cardGoneTimer < cardGoneTimerLimit + 1 then 
			beep(500)
			cardState = isCardIn()
			if cardState == 1 then 
				cardGoneTimer = 0 
				setState(state_acquire)
			end
		else 
			cardGoneTimer = 0
			if checkConnection() == false then 
				setState(state_noConnection) 
				return
			else	
				setState(state_idle)
				return 
			end
		end		
	end
	
	if state == state_newEntry then
		--nothing yet
	end   

	print("State: ", state)
	tmr.delay(10000)	
end

function sendRequestToServer()
    if ID ~= nil and ID ~= "" then
        setLED("card", "blink")
        if  timeEnabled == 0 or timeEnabled >= ttl then
            timeEnabled = 0
            requestURL = "http://192.168.1.72/api/v1/users/allowed/"..ID.."/"..macAddress
            print("Sending request to server")
            waitingForAnswer = true
            waitingTimeoutCounter = 0
            http.get(requestURL, "Authorization: Basic "..header.."\r\n", function(code, data)
                print("Got answer from server")
				permission = 0
				
                if data ~= nil then
                    dataDecoded = cjson.decode(data)
                    for k,v in pairs(dataDecoded) do 
                        if k == "status" then permission = v end
                        if k == "ttl" then ttl = v end            
                    end
                    print(permission, " ", ttl)
					if ttlOverride > 0 then ttl = ttlOverride end
                else
                    print("No data received from server")
                end
				
				if permission == false then 
					setState(state_idle)
				elseif permission == true then
					setState(state_enabled)
					waitingForAnswer = false
				end	
				
				timeEnabled = 0
            end)
         end   
    end
end

function setState(newState)
	if newState == state then return end
	print("New state: " , newState)
	state = newState
end


function setStateByCard(cardState)
	if cardState == 0 then 
		setState(state_idle)
	elseif cardState == 1 then
		setState(state_acquire)
	elseif cardState == 2 then
		setState(state_cardGone)
	end	
end

function isCardIn()
    oldID = ID
    ID = RC522.get_ID() 

    if ID == nil or ID == "" then
        if oldID ~= ID then 
            return 2
		else
			return 0
        end
    else
	    ID = appendHex(ID)
		return 1
    end
end

function createConnection() --TODO: check if resets when failed
    print("Creating connection...")
    wifi.setmode(wifi.STATION, false)
    wifi.sta.config(station_cfg)
    checkConnection()
end

function checkConnection()
    if wifi.sta.status() ~= wifi.STA_GOTIP then 
	    print("Connection status", wifi.sta.status())
	    setLED("server", "off") 
		return false
    else
	    setLED("server", "on")
		return true
    end    
end

function beep(duration)
    --duration = duration *1000
	if silentBeep == true then 
		print("BEEP") 
	else
		gpio.write(beeperPin, gpio.HIGH)
	end
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

function appendHex(t) --  Converts a table of numbers into a HEX string
  if t[4] ~= nil then
    strT = (t[4] * (256^3)) + (t[3] * (256^2)) + (t[2] * (256^1)) + (t[1] * (256^0)) 
    return string.format("%u", strT)
  end
  return ""
end



function setRelay(permission)
    if permission == 1 then
        gpio.write(RelayInPin, gpio.HIGH)
    else
        gpio.write(RelayInPin, gpio.LOW)
    end
end

boot()

tmr.alarm(0, 1000, tmr.ALARM_AUTO, function()
   mainLoop()
end)