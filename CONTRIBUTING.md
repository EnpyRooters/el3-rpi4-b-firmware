Overview

Thank you for your interest in contributing!
This project implements an experimental Arm Trusted Firmware environment for the Raspberry Pi 4 B.
it exposes a simple kernel-module interface via /dev.
At this stage (alpha → beta), contributions are welcome, but please follow these safety and build guidelines carefully.


---

Safety Notice

Do not run on production devices. Use a spare Raspberry Pi 4 B.

The firmware interacts directly with EL3 and could leave your device unbootable if interrupted.

Always back up your SD card before testing.

Never redistribute modified binaries without clear versioning and checksums.



---

Requirements

Tool	Minimum Version	Notes

GCC	10+ (aarch64-none-elf)	Required cross-compiler
Python	3.8+	Used by the build script
Git	any recent version	For source control
Raspberry Pi 4 B	64-bit mode	Target hardware
systemd	available on target OS	Used to launch firmware service



---

Building

1. Go to the the repo and then the lasest release .zip file:

https://github.com/EnpyRooters/el3-rpi4-b-firmware


2. Read and follow BUILD.md.
It contains the full build flow using the provided Python script.


3. Run the Python build helper in the latest release .zip archive in github/bl3_v0.3-master/src (also the source code):

sudo python3 make.py


4. The script compiles and assembles all components into an image in build/.
Optional but recommend. delete ./build after compilation.

---

Testing

Use the supplied systemd service file located in service/.

Copy it to /etc/systemd/system/ and enable it only on a test device:

sudo systemctl enable --now atf-firmware.service

Check logs with:

journalctl -u aft-firmware.service

Verify that EL3 initializes and no kernel traps occur.

---

Versioning:

vX.X.X

Semantic versioning: MAJOR.MINOR.PATCH
Use pre-release tags (-alpha, -beta, -rc) until v1.0.0.