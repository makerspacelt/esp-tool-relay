FILES=Main.lua RC522.lua


flash: nodemcu.bin
	sudo esptool.py --port /dev/ttyUSB0 write_flash -fm dio 0x00000 $^

upload: $(FILES)
	sudo nodemcu-uploader --port=/dev/ttyUSB0 upload $^

run:
	sudo nodemcu-uploader --port=/dev/ttyUSB0 file do Main.lua

connect:
	sudo minicom --noinit -b 115200 -D /dev/ttyUSB0

