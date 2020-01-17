require "RC522"
require "Login1"

--wifi
station_cfg = {}
station_cfg.ssid = Login1.username
station_cfg.pwd = Login1.password
macAddress = wifi.sta.getmac()
header = Login1.header

timeWithoutConnection = 0
timeWithoutConnectionLimit = 10

timeEnabled = 0
cardGoneTimer = 0
cardGoneTimerLimit = 3
waitingForAnswer = false
waitingTimeoutCounter = 0
ttl = 10
ttlOverride = 10 --0 if disabled

ID = nil

silentBeep = true

--new Entry globals
newEntryCounter = 0
newEntryCounterTimeout = 10
adminID = nil
askerID = nil

--device states
	state_boot = "boot"
	state_noConnection = "no connection"
	state_idle = "idle"
	state_acquire = "acquiring permission"
	state_enabled = "relay enabled"
	state_cardGone = "card gone"
	state_newEntry = "new entry"
state = -1 

--pins
	--D7 MOSI
	--D8 SDA
	--D5 SDK
	--D6 SOI
	--RST 3.3V
beeperPin = 1
RelayInPin = 0
RelayVCCPin = beeperPin
powerLEDpin = 4
connectionLEDpin = 3 
cardLEDpin = 2
LEDblinkDuration = 500

--timer objects
tmr_mainLoop = tmr.create();
tmr_buttonCheck = tmr.create();

leds = {
  power = { pin = powerLEDpin },
  server = { pin = connectionLEDpin },
  card = { pin = cardLEDpin },
}

for name, led in pairs(leds) do
	led.pressed = false
	led.on = false
	led.timer = tmr.create()
	led.timer:register(
		LEDblinkDuration,
		tmr.ALARM_AUTO,
		function()
			gpio.write(led.pin, led.on and gpio.LOW or gpio.HIGH)
			led.on = not led.on
		end
	)
end

--default pin states
gpio.mode(beeperPin, gpio.OUTPUT)
gpio.mode(RelayInPin, gpio.OUTPUT)
gpio.mode(RelayVCCPin, gpio.OUTPUT)
gpio.mode(powerLEDpin, gpio.OUTPUT)
gpio.mode(connectionLEDpin, gpio.OUTPUT)
gpio.mode(cardLEDpin, gpio.OUTPUT)

gpio.write(beeperPin, gpio.LOW)
gpio.write(RelayInPin, gpio.LOW)
gpio.write(RelayVCCPin, gpio.LOW)

function test()
	tmr.create():alarm(1000, tmr.ALARM_AUTO, function()
		print("hello")
		rfswitch.send(1, 300, 5, beeperPin, 74, 10)
	end)
end	
	
function boot()		
	setState(state_boot)
	
	setLED("power", "on")
	setLED("server", "on")
	setLED("card", "on")
	beep(100, true)
	
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
			if timeWithoutConnection >= timeWithoutConnectionLimit then
				timeWithoutConnection = 0
				createConnection()
			end
			timeWithoutConnection = timeWithoutConnection + 1
		end
	
	elseif state == state_idle then
		setRelay(0)
		setLED("card", "off") 
	
		if checkConnection() == false then setState(state_noConnection) end
		
		setStateByCard(isCardIn())
		if state == state_idle then setStateByButton() end
	
		
	elseif state == state_acquire then
		timeEnabled = 0
		if waitingForAnswer == false then
			sendRequestToServer()
		else
			waitingTimeoutCounter = waitingTimeoutCounter +1
		end
		if waitingTimeoutCounter > 8 then waitingForAnswer = false end
		if checkConnection() == false then setState(state_noConnection) end
	
	
	elseif state == state_enabled then
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
			
	elseif state == state_cardGone then
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
		
	elseif state == state_newEntry then		
		if newEntryCounter == 0 then 
			beep(100) 
			adminID = nil
			askerID = nil
		end
		newEntryCounter = newEntryCounter + 1
		if newEntryCounter >= newEntryCounterTimeout then 
			newEntryCounter = 0
			waitingForAnswer = false
			beep(100, true)
			tmr.delay(500) 
			beep(100, true)
			print("Timeout!")
			setState(state_idle) 
		else
			if adminID == nil then
				print("waiting for admin ID")
				--print(isCardIn(), " ID ", ID)
				if isCardIn() == 1 then 
					adminID = ID 
					print("adminID set") 
				end
			else
				if askerID == nil then 
					print("waiting for asker ID")
					if isCardIn() == 1 then 
						if ID ~= adminID then
							askerID = ID
							print("asker ID set") 
						end
					end
				end
			end
			
			if adminID ~= nil and askerID ~= nil and waitingForAnswer == false then
				beep(100)
				print("Sending to server:")
				print("adminID ", adminID)
				print("askerID ", askerID)
				waitingForAnswer = true
				requestURL = "http://192.168.1.72/api/v1/users/grant/"..adminID.."/"..askerID.."/"..macAddress				
				http.get(requestURL, "Authorization: Basic "..header.."\r\n", function(code, data)
					waitingForAnswer = false
					print("Got answer from server:")
					grant = false
					print(data)
					if data ~= nil then
						local success, dataDecoded = pcall(sjson.decode, data) 
						if success then
							for k,v in pairs(dataDecoded) do 
								if k == "status" then grant = v end          
							end	
						else
							print("json decode error, dataDecoded: ", dataDecoded)
						end
					else
						print("No data")
					end
					
					if grant == true then
						beep(100, true)
					else
						beep(1000, true)
						setState(state_idle)
					end
				end)				
			end
		end
	end   

	print("State: ", state, node.heap())
	tmr.delay(10000)	
end

function setStateByButton()
	setButtonFlags()	
	
	if leds["power"].pressed == 0 then
		setState(state_newEntry)
	end
end

function sendRequestToServer()
    if ID ~= nil and ID ~= "" then
        if  timeEnabled == 0 or timeEnabled >= ttl then
            timeEnabled = 0
            requestURL = "http://192.168.1.72/api/v1/users/allowed/"..ID.."/"..macAddress
            print("Sending request to server")
            waitingForAnswer = true
            waitingTimeoutCounter = 0
			setLED("card", "blink")
            http.get(requestURL, "Authorization: Basic "..header.."\r\n", function(code, data)
                print("Got answer from server:")
				permission = 0
				
                if data ~= nil then
                    dataDecoded = sjson.decode(data)
                    for k,v in pairs(dataDecoded) do 
                        if k == "status" then permission = v end
                        if k == "ttl" then ttl = v end            
                    end
                    print(permission, " ", ttl)
					if ttlOverride > 0 then ttl = ttlOverride end
                else
                    print("No data")
                end
				
				if permission == false then 
					setState(state_idle)
				elseif permission == true then
					setState(state_enabled)
				end	
				waitingForAnswer = false
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
	    --print("Connection status", wifi.sta.status())
	    setLED("server", "off") 
		return false
    else
	    setLED("server", "on")
		--ip = wifi.sta.getip()
		--print(ip)
		return true
    end    
end

function beep(duration, waitToEnd)
    --duration = duration *1000
	if silentBeep == true then 
		print("BEEP") 
	else
		gpio.write(beeperPin, gpio.HIGH)
	end
	if waitToEnd == true then 
		tmr.delay(duration * 1000) 
		gpio.write(beeperPin, gpio.LOW)
	else	
		tmr.create():alarm(duration, tmr.ALARM_SINGLE, function()
			gpio.write(beeperPin, gpio.LOW) 			
		end)
	end
end

function setLED(led, state)
    if state == "off" then gpio.write(leds[led].pin, gpio.HIGH) leds[led].on = false end
    if state == "on" then gpio.write(leds[led].pin, gpio.LOW) leds[led].on = true end
	
	if state == "blink" then
		leds[led].timer:start()
	else
		leds[led].timer:stop()
    end
end

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

function setButtonFlags()
	for name, led in pairs(leds) do
		gpio.mode(led.pin, gpio.INPUT, gpio.PULLUP)
		led.pressed = gpio.read(led.pin)
		
		gpio.mode(led.pin, gpio.OUTPUT)
		if led.on == true then 
			gpio.write(led.pin, gpio.LOW)
		else	
			gpio.write(led.pin, gpio.HIGH)
		end      		
	end
end

test()

-- boot()



-- tmr_mainLoop:alarm(1000, tmr.ALARM_AUTO, function()
   -- mainLoop()
-- end)