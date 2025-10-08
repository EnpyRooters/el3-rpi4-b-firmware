# el3-rpi4-b-firmware
This is firmware source code that is in it's early development stages that initiates el3 on the Raspberry Pi 4 B. This firmware is tested before release.

# building
commands:
git clone https://github.com/EnpyRooters/el3-rpi4-b-firmware

cd el3-rpi4-b-firmware

sudo python3 make.py

objcopy -O binary --only-section=.text --gap-fill=0x00 aft_firmware atf.bin

# using
DANGER! MAY BRICK OR CAUSE BOOT FAILURE!

sudo mv ./atf.bin /boot/firmware

sudo nano /boot/firmware/config.txt

then add

armstub=atf.bin
armstub_addr=0x88000
kernel=kernel*.img
kernel_addr=0x200000

under [all] in config.txt

than

sudo reboot
