FILES=init_.lua RC522.lua Login1.lua


.PHONY: flash
flash: nodemcu.bin
	sudo esptool.py -b 460800 write_flash -fm dio 0x00000 $^

.PHONY: upload
upload: $(FILES) reset
	sudo nodemcu-uploader --baud 230400 upload $(FILES)

.PHONY: run
run:
	sudo nodemcu-uploader file do Main.lua

.PHONY: connect
connect:
	sudo nodemcu-uploader terminal

.PHONY: reset
reset:
	sudo esptool.py --no-stub read_mac


