# Oh I'm Smart: a ThinkSmart View voice terminal

[简体中文](README.md) | [繁體中文](README.zh-Hant.md) | English

Turn a Lenovo **ThinkSmart View (model CD-18781Y)** into a local voice assistant: it boots straight into the voice interface, wakes up on "小麦小麦" (*Xiǎo Mài Xiǎo Mài*), and can talk to Claude, DeepSeek and many other large language models.

Oh I'm Smart is an extended version of [justhalfbit/thinksmart-ubuntu-image](https://github.com/justhalfbit/thinksmart-ubuntu-image). The image is based on [rickx/ubuntu-thinksmart](https://github.com/rickx/ubuntu-thinksmart) (Ubuntu 24.04 + postmarketOS kernel 6.19), without the Plasma desktop, and comes with:

- the voice client [ohimsmart/oh-im-smart-client](https://github.com/ohimsmart/oh-im-smart-client) (from [justhalfbit/xiaozhi-thinksmart-client](https://github.com/justhalfbit/xiaozhi-thinksmart-client)): wake word, conversation screen, sleep hours, brightness, online updates;
- the Xiaozhi hub [ohimsmart/oh-im-smart-gateway](https://github.com/ohimsmart/oh-im-smart-gateway) (from [justhalfbit/xiaozhi-hub-server](https://github.com/justhalfbit/xiaozhi-hub-server)): on-device speech recognition, connects to LLM and text-to-speech providers, with a web admin page;
- device fixes: both microphones, the speaker, screen blanking and proximity wake, Wi-Fi stability, GPU white-screen/freeze patches and more.

The interface comes in Traditional Chinese, Simplified Chinese and English, chosen on first boot; the wake word "小麦小麦" is Chinese only.

> ⚠️ Flashing wipes the original Teams / Android system. Before the first flash, **back up the whole eMMC** ([A2](#a2-back-up-the-whole-stock-emmc-required)). It is the only way back to the stock system later.

This README is the complete flashing guide, written so that a person or an AI agent can follow it step by step.

---

## Contents

- [For AI agents (read this first)](#for-ai-agents-read-this-first)
- [0. Preparation](#0-preparation)
- [1. Enter EDL mode and pick a route](#1-enter-edl-mode-and-pick-a-route)
- [Route A: first flash (device still on the stock system)](#route-a-first-flash-device-still-on-the-stock-system)
- [Route B: device already runs this image or the upstream Ubuntu image](#route-b-device-already-runs-this-image-or-the-upstream-ubuntu-image)
- [2. First boot and setup](#2-first-boot-and-setup)
- [3. Troubleshooting](#3-troubleshooting)
- [4. Back up and restore user data](#4-back-up-and-restore-user-data)
- [5. Updates](#5-updates)
- [Appendix: partitions and image layout](#appendix-partitions-and-image-layout)
- [Credits and notices](#credits-and-notices)

---

## For AI agents (read this first)

If you are an AI agent the owner asked to help with flashing, read this whole section before starting at step 0.

### Goal

Write the image from this repository's Releases to the `system` partition of the owner's ThinkSmart View so that it boots into the voice assistant, then help the owner through first-time setup (screen language, Wi-Fi, hub admin password, API key, new default password, time zone).

### Overall flow

```
Step 0  Preparation: check the model → install edl → download and verify the files
Step 1  Enter EDL mode → edl printgpt → pick a route by the size of the system partition
  Route A (stock system): full backup → lk2nd to boot → (optional) prepare the bootstrap with prepare.sh
                          → bootstrap to system → boot → SSH into the bootstrap, rewrite the partition table
                          → power off → EDL again → this image to system
  Route B (already Ubuntu): (optional) back up user data → EDL → this image to system
Step 2  First boot: choose the screen language → Wi-Fi on the screen → find the IP → hub admin password and API key
        → change the ubuntu password, set the time zone → try voice
```

### Operations that need the owner's explicit yes first

Each of these is irreversible or wipes data. Before running one, tell the owner **the exact command** and **what it does**, and wait for a clear "yes / go ahead / do it". One yes covers that one step only; ask again for the next.

| Step | Operation | Consequence |
| --- | --- | --- |
| A2 | The full-backup target file already exists | The old backup is overwritten and gone. By default use another file name instead |
| A3 | `edl w boot lk2nd.img` | The stock boot chain is replaced by lk2nd; Android/Teams will no longer boot |
| A4 | `edl w system <BOOTSTRAP_IMAGE>` (the downloaded one or the one `prepare.sh` made) | The stock `system` partition is overwritten |
| A6 | Running `apply-ubuntu-gpt.sh` in the bootstrap | The whole partition table is rewritten; the stock vendor, cache, userdata and other partitions are deleted |
| A8 / B3 | `edl w system thinksmart-ubuntu-…img` | Everything on `system` is overwritten (including chat history, API keys and Wi-Fi settings of the old system) |
| — | Any `edl wf` (write back the whole disk) | The entire eMMC is overwritten. Only when the owner explicitly asks to return to stock |

Also stop and ask when:

- the output of any step doesn't match the "expected output" in this guide;
- a write command has failed once. You may explain and suggest one retry; if it fails again, stop. Don't keep retrying.

### Things the owner must do by hand

An AI agent can't do these. At these points tell the owner exactly what to do and wait until they say it's done:

- plug and unplug the USB cable and the power cable, try another cable or another USB port on the computer;
- the button combination for EDL mode (unplug the power cable → connect the USB cable → hold Volume + and Volume − → plug in the power cable → release the volume buttons after 3–5 seconds; see 1.1);
- powering off and on: the device has **no power button**; plugging in the power cable turns it on. While the system is running, shut it down before unplugging: tap "Shut down" at the bottom of the voice interface's settings, or run `sudo systemctl halt` over SSH, and unplug 10 seconds after the screen goes black (the system takes a few more seconds to finish). Wait about 30 seconds before plugging it back in; plugged straight back in, it may not power on. Don't use `sudo poweroff`: with the cable in, the device powers straight back on. Only unplug without shutting down when you can't (emergency mode, the lk2nd screen);
- look at the device screen and tell you what it shows (black, lk2nd screen, welcome page, voice interface…);
- choose the screen language on the device on first boot;
- pick the Wi-Fi network and type its password on the device's touchscreen;
- answer `prepare.sh`'s questions (Wi-Fi name, Wi-Fi password, the bootstrap login password);
- open the hub admin page in a browser, set the admin password, enter the API key;
- say "小麦小麦" to the device to confirm voice works;
- click "Allow" when macOS asks "Allow accessory to connect?", and "Yes" on a Windows UAC prompt.

### Never do these on your own

- Don't use `edl w` on any partition other than `boot` and `system`; don't use `edl e` (erase), `edl wl`, `edl qfp` or other bulk-write commands.
- Don't flash or erase with fastboot: no `fastboot flash`, `fastboot erase` or `fastboot oem unlock`. The bootloader is locked, fastboot can't write anything, and trying only causes trouble.
- Don't run `apply-ubuntu-gpt.sh` again on a device whose partition table was already rewritten, and don't run `sfdisk`, `dd` or `parted` on `/dev/mmcblk0` yourself.
- Don't delete, move or overwrite the stock full backup `stock-full-emmc.bin`, and never upload it anywhere. It holds data unique to this device (serial numbers, calibration data, accounts from the stock system).
- Don't write the owner's Wi-Fi password, API key or device passwords into logs or repositories, or send them to any third-party service.
- Don't answer `prepare.sh`'s questions for the owner, and don't put the Wi-Fi password or the login password into commands, files or notes. Delete the bootstrap copy `prepare.sh` made once it has served (after A8).
- Don't modify downloaded image files. If a checksum doesn't match, download again.
- Never ask the owner to unplug or power off during a write.

### Working rules

- For each step run the "command", then compare with the "expected output" and "how to tell it worked". Move on only when they match; otherwise see "if it fails", and if that doesn't solve it, stop and ask the owner.
- Save the full output of every `edl` command (`2>&1 | tee LOGFILE`) to show the owner if something goes wrong.
- **Find the device's IP yourself; don't ask the owner**: work out the subnet from the computer's own IP, then scan the LAN in two stages. The bootstrap (A5) only opens port 22: use `nmap -p 22 --open <SUBNET, e.g. 192.168.1.0/24>`; its host name is `thinksmarter`. Once this image is flashed, use `nmap -p 22,16688 --open <SUBNET>`, then open `http://<IP>:16688/admin` and check that the page title is "Xiaozhi Hub Admin". Exact commands, and what to do without nmap, are in [2.3](#23-find-the-devices-ip-address).
- Commands assume a macOS / Linux terminal. On Windows use PowerShell: after setting up `edl` as in [0.2 Windows](#windows-1011-untested), copy `edl` commands as they are; for the others use this table:

  | macOS / Linux | Windows PowerShell |
  | --- | --- |
  | `shasum -a 256 FILE` | `Get-FileHash FILE -Algorithm SHA256` |
  | `ls -l FILE` | `(Get-Item FILE).Length` |
  | `grep TEXT FILE` | `Select-String TEXT FILE` |
  | `python3` | `python` |
  | `ping -c 3 ADDRESS` | `ping -n 3 ADDRESS` |
  | `xz -dk FILE.xz` | unpack with 7-Zip |
  | `… 2>&1 \| tee LOG` | same (in PowerShell `tee` is `Tee-Object`) |

- The Windows parts were **not tested** by this project; they follow edl's and upstream's documentation and are marked "Windows untested". If things don't match, the easiest fix is to flash from a macOS or Linux computer instead.
- The owner already runs this image and just wants a newer one? Go to [Route B](#route-b-device-already-runs-this-image-or-the-upstream-ubuntu-image), but still do steps 0 and 1 first.

---

## 0. Preparation

### 0.1 Check the device model

Only the **Lenovo ThinkSmart View CD-18781Y** is supported: 8-inch portrait screen, Qualcomm APQ8053, 2 GB RAM, 8 GB eMMC.

- The label on the back or bottom of the device says **CD-18781Y**.
- After entering EDL (step 1), the output of `edl printgpt` contains `CPU detected: "APQ8053"` and `total_blocks:15269888`. If either differs, **this is not the right device: stop**.
- Devices with a model number other than CD-18781Y (including the ThinkSmart View Plus) were not tested; don't flash them.

### 0.2 Computer and tools

You need:

- a macOS, Linux or Windows computer with **at least 20 GB free** (stock full backup about 7.3 GB, bootstrap image about 1 GB, another 1 GB or so for the copy `prepare.sh` makes if you use it, this image about 0.7 GB compressed and 3.5 GB unpacked);
- a USB cable **that carries data** (USB-C on the device side), plugged straight into the computer, not through a dock or hub;
- [bkerler/edl](https://github.com/bkerler/edl), the Qualcomm EDL flashing tool; install commands per system below;
- a tool for `.xz` files and an SSH client (macOS, Linux and Windows 10/11 all come with SSH).

#### macOS

```bash
brew install libusb xz git
python3 -m venv ~/edl-venv
source ~/edl-venv/bin/activate
git clone https://github.com/bkerler/edl.git ~/edl-src
cd ~/edl-src && git submodule update --init --recursive
pip install .
```

In every new terminal, run `source ~/edl-venv/bin/activate` first so that the `edl` command is available.

If `pip install .` fails on the newest Python, use Python 3.12: `brew install python@3.12`, replace `python3 -m venv` above with `python3.12 -m venv`, and run the steps again.

#### Linux (Debian / Ubuntu)

```bash
sudo apt install git xz-utils python3-venv python3-dev liblzma-dev libusb-1.0-0
sudo systemctl disable --now ModemManager    # ModemManager grabs the EDL device
git clone https://github.com/bkerler/edl.git ~/edl-src
cd ~/edl-src && git submodule update --init --recursive
sudo bash ./install-linux-edl-drivers.sh     # udev rules, so normal users can access the EDL device
python3 -m venv ~/edl-venv
source ~/edl-venv/bin/activate
pip install .
```

Unplug and replug the USB cable after installing the udev rules. If it still says permission denied, put `sudo` in front and use the full venv path: `sudo ~/edl-venv/bin/edl …`.

#### Windows 10/11 (untested)

The upstream author flashed from Windows (upstream FLASHING.md uses PowerShell commands). This project has not tested Windows; the steps below are put together from edl's source and documentation.

Don't use edl's one-click script `install_edl_win10_win11.ps1` as it is. It installs Python 3.9 while edl needs 3.10 or newer, and the `edl.bat` it puts on PATH calls a file that no longer exists in edl 3.62, so typing `edl` fails with "file not found". Use these manual steps instead, in PowerShell (not CMD):

```powershell
winget install -e --id Python.Python.3.12
winget install -e --id Git.Git
winget install -e --id akeo.ie.Zadig
winget install -e --id 7zip.7zip
```

Close PowerShell, open it again, then:

```powershell
git clone https://github.com/bkerler/edl.git $env:USERPROFILE\edl-src
cd $env:USERPROFILE\edl-src
git submodule update --init --recursive
py -3.12 -m venv $env:USERPROFILE\edl-venv
& $env:USERPROFILE\edl-venv\Scripts\python.exe -m pip install -r requirements.txt
```

In every new PowerShell window, run these two lines first. After that the `edl …` commands in this guide work as written:

```powershell
& $env:USERPROFILE\edl-venv\Scripts\Activate.ps1
function edl { python "$env:USERPROFILE\edl-src\edl.py" @args }
```

If `Activate.ps1` says running scripts is disabled, run `Set-ExecutionPolicy -Scope Process Bypass` first (applies to the current window only).

USB driver: the first time the device is in EDL (step 1.1), install the WinUSB driver for it with Zadig so that edl can reach it. edl ships the Windows libusb library itself; nothing else to install.

Why not WSL: WSL2 doesn't see USB devices by default and needs usbipd-win to pass them through; the EDL device reconnects during flashing and the pass-through drops easily. Running edl natively on Windows is more reliable.

#### Check that edl works

```bash
edl --help
```

Expected: the output starts with `Qualcomm Sahara / Firehose Client`, followed by a long usage text. If `edl` is not found: on macOS / Linux run `source ~/edl-venv/bin/activate` first; on Windows run the two "every new PowerShell window" lines above.

#### Docker (only if you want `prepare.sh` in A4)

`prepare.sh` modifies the bootstrap image inside a Docker container, so it needs Docker. If you only reach the bootstrap over the USB cable, skip this.

- macOS: install Docker Desktop, accept the license on first start, and wait until it says it is running:

  ```bash
  brew install --cask docker-desktop
  ```

- Linux: install Docker Engine, add yourself to the `docker` group, then log out and back in:

  ```bash
  sudo apt install docker.io
  sudo usermod -aG docker $USER
  ```

- Windows: untested.

Docker is ready when `docker info` runs without an error.

### 0.3 Download the files

Create a working directory such as `~/thinksmart` and put all the files below in it. All later commands run in this directory.

| File | Where | Needed for |
| --- | --- | --- |
| `thinksmart-ubuntu-<DATE>.img.xz`, `SHA256SUMS` | latest release in this repository's [Releases](https://github.com/ohimsmart/oh-im-smart/releases) | both routes |
| `lk2nd.img` | upstream [prebuilt/lk2nd.img](https://github.com/rickx/ubuntu-thinksmart/raw/main/prebuilt/lk2nd.img) | route A only |
| `bootstrap-pmos-ssh-generic-qcom-msm8953.img` and its `.sha256` | upstream release [bootstrap-2026-05-22](https://github.com/rickx/ubuntu-thinksmart/releases/tag/bootstrap-2026-05-22) | route A only |

No separate partition table files are needed: the bootstrap image already contains the GPT rewrite script `/usr/local/sbin/apply-ubuntu-gpt.sh` and its layout file.

```bash
mkdir -p ~/thinksmart && cd ~/thinksmart
curl -L -O https://github.com/rickx/ubuntu-thinksmart/raw/main/prebuilt/lk2nd.img
curl -L -O https://github.com/rickx/ubuntu-thinksmart/releases/download/bootstrap-2026-05-22/bootstrap-pmos-ssh-generic-qcom-msm8953.img
curl -L -O https://github.com/rickx/ubuntu-thinksmart/releases/download/bootstrap-2026-05-22/bootstrap-pmos-ssh-generic-qcom-msm8953.img.sha256
# This image: copy the download links of the two files of the latest release from the Releases page, and download them with curl -L -O as well
```

In Windows PowerShell write `curl` as `curl.exe`; everything else stays the same. If GitHub is blocked or slow where you are, add a proxy to curl with `-x http://<PROXY>:<PORT>`, or download in a browser and move the files into this directory.

### 0.4 Verify the files

```bash
cd ~/thinksmart
shasum -a 256 -c --ignore-missing SHA256SUMS          # on Linux sha256sum works too
shasum -a 256 bootstrap-pmos-ssh-generic-qcom-msm8953.img lk2nd.img
cat bootstrap-pmos-ssh-generic-qcom-msm8953.img.sha256
```

Expected output:

- the first command prints `thinksmart-ubuntu-<DATE>.img.xz: OK`;
- the bootstrap image's SHA256 equals the value in the `.sha256` file: `7d79db19b0911647bf6ab0a9a2924ef5cf83b4674798a54acdcbd41cdf07921b`;
- the SHA256 of `lk2nd.img` is `c81b036c75028c3d5aa915c72c89e075bc044360fe964c2ec0afb1d4a6f5209b`. That is upstream's version at the time of writing; if upstream updates lk2nd later, upstream wins.

On Windows compute each one with `Get-FileHash .\FILENAME -Algorithm SHA256` and compare with the values above.

If any of them doesn't match, download that file again; don't use it.

### 0.5 Unpack the image

```bash
xz -dk thinksmart-ubuntu-<DATE>.img.xz
shasum -a 256 -c --ignore-missing SHA256SUMS
```

Expected: two lines, `.img.xz: OK` and `.img: OK`. The unpacked `.img` is about 3.5 GB; the release notes give each version's sizes. On Windows unpack with 7-Zip, then compare `Get-FileHash` with the `.img` line in `SHA256SUMS`.

The `.img` is the content of the whole `system` partition and holds two small partitions, boot and root. On first boot the root partition grows to fill the whole `system` partition.

---

## 1. Enter EDL mode and pick a route

### 1.1 Enter EDL (owner does this)

The device has no power button: plugging in the power cable turns it on, unplugging it cuts the power.

1. Unplug the power cable. If the system is running, shut it down first ("Shut down" in the settings or `sudo systemctl halt`) and unplug 10 seconds after the screen goes black. If the USB cable is plugged in, unplug it too. Then wait 30 seconds before the next steps; plugged straight back in after a shutdown, it may not power on and won't enter EDL.
2. Connect the device to the computer with the USB cable.
3. **Hold Volume + and Volume − together** and keep holding.
4. While holding them, plug in the power cable.
5. Release the volume buttons after 3–5 seconds.

**The screen stays black; that's normal.** EDL mode shows nothing.

Check that the computer sees the device:

- macOS: `ioreg -p IOUSB | grep -i -E "qhsusb|qusb|9008"` should show `QUSB__BULK` or `QHSUSB__BULK`. On Apple Silicon Macs, click "Allow" when asked "Allow accessory to connect?".
- Linux: `lsusb | grep -i 9008` should show `Qualcomm ... (QDL mode)` or `05c6:9008`.
- Windows (untested): Device Manager shows `QUSB__BULK` (usually with a yellow exclamation mark) or `Qualcomm HS-USB QDLoader 9008`. **The first time**, install the WinUSB driver: open Zadig → menu Options, tick List All Devices → pick `QUSB__BULK` in the drop-down (USB ID `05C6 9008`) → choose `WinUSB` as the driver on the right → click Install Driver (it says Replace Driver if another driver is installed). Once is enough.

Not there? See [3.1 edl can't find the device](#31-edl-cant-find-the-device-or-loses-it-right-after-connecting).

### 1.2 Read the partition table

```bash
cd ~/thinksmart
edl printgpt 2>&1 | tee gpt-before.txt
```

Expected output (excerpt):

```
main - Device detected :)
...
CPU detected:      "APQ8053"
...
firehose - TargetName=MSM8953
firehose - total_blocks:15269888
...
boot:                Offset 0x0000000018200000, Length 0x0000000002000000, ...
system:              Offset 0x000000001c300000, Length 0x…, ...
```

How to tell it worked: `Device detected :)` appears and a partition list is printed. If `CPU detected` isn't `APQ8053` or `total_blocks` isn't `15269888`: **stop, this device is not supported**.

### 1.3 Pick a route

Look at the `Length` on the `system:` line:

| `system` Length | `userdata:` line? | Meaning | Route |
| --- | --- | --- | --- |
| `0x0000000060000000` (1.5 GB) | yes | stock partition table | [Route A](#route-a-first-flash-device-still-on-the-stock-system) |
| `0x00000001b3cfbe00` (about 6.8 GB) | no | already the Ubuntu partition table | [Route B](#route-b-device-already-runs-this-image-or-the-upstream-ubuntu-image) |
| anything else | — | unknown partition table | **stop**, show the output to the owner, don't continue |

---

## Route A: first flash (device still on the stock system)

> Experimental: not tested by Oh I'm Smart on a stock device. Route A follows upstream's steps; the Oh I'm Smart maintainers have not yet gone through it from start to finish on a device still running the stock system.

Exactly the same order as upstream:

```
full backup → lk2nd to boot → bootstrap to system → boot the bootstrap
→ SSH in and rewrite the partition table → power off → EDL again → this image to system
```

Why the detour: the stock `system` partition is only 1.5 GB, too small for Ubuntu. A small temporary system (the bootstrap, postmarketOS) is flashed first and rewrites the partition table on the device to a layout with a `system` of about 6.8 GB; then the real image goes in.

### A1. Enter EDL

As in [1.1](#11-enter-edl-owner-does-this). If you just finished step 1 and the cable hasn't been unplugged, carry on directly.

### A2. Back up the whole stock eMMC (required)

This is the **only way** back to the stock system later.

```bash
cd ~/thinksmart
ls -l stock-full-emmc.bin 2>/dev/null && echo "stock-full-emmc.bin exists: use another name, don't overwrite it"
edl rf stock-full-emmc.bin 2>&1 | tee backup.log
```

- Takes about 10–20 minutes; don't touch the cable.
- Expected: the output ends with `Dumped flash with sector count 15269888 as stock-full-emmc.bin.`

Check that the backup is complete; all three must hold:

```bash
ls -l stock-full-emmc.bin
python3 -c "f=open('stock-full-emmc.bin','rb'); f.seek(512); print(f.read(8))"
shasum -a 256 stock-full-emmc.bin | tee stock-full-emmc.bin.sha256
```

1. The file is exactly `7818182656` bytes, i.e. `15269888 × 512`;
2. the second command prints `b'EFI PART'`: the backup starts with a complete GPT;
3. the third saves the checksum in `stock-full-emmc.bin.sha256`, to check later that the backup is still intact.

(Windows: `(Get-Item .\stock-full-emmc.bin).Length` for the size, the `python -c …` line as is, `Get-FileHash` for the checksum.)

Where to keep it:

- in `~/thinksmart` together with `gpt-before.txt`, **plus a copy on an external drive or another computer**;
- not in cloud storage or anywhere public: it contains data unique to this device.

To go back to stock later: in EDL run `edl wf stock-full-emmc.bin` to write the whole disk back, only with the owner's yes.

If it fails:

- Error or disconnect midway: unplug, enter EDL again, try another cable or port, run it again (with another file name).
- Wrong size or no `EFI PART`: the backup is incomplete; delete it and redo it. **Don't go further until the backup is done.**

### A3. Flash lk2nd to the boot partition (ask the owner first)

lk2nd is a secondary bootloader that boots Linux from the `system` partition.

```bash
edl w boot lk2nd.img 2>&1 | tee flash-lk2nd.log
```

Expected: the output ends with `Wrote lk2nd.img to sector 790528.`

If it fails:

- `Couldn't detect partition: boot`: the partition table wasn't read correctly; run `edl printgpt` again and look.
- Any other error: enter EDL again and retry once; if it still fails, stop.

### A4. Flash the bootstrap image to the system partition (ask the owner first)

First choose which bootstrap image to flash:

1. **USB cable only**: flash the downloaded `bootstrap-pmos-ssh-generic-qcom-msm8953.img` and go straight to the flash command below.
2. **Let the bootstrap use Wi-Fi as well (experimental: not tested by Oh I'm Smart on a stock device)**: when the USB network doesn't work (Windows not recognizing it, for example), the bootstrap can use Wi-Fi instead. Make a prepared copy with this repository's `prepare.sh` (install Docker first, see 0.2):

   ```bash
   git clone https://github.com/ohimsmart/oh-im-smart.git ~/oh-im-smart
   cd ~/thinksmart
   ~/oh-im-smart/bootstrap/prepare.sh bootstrap-pmos-ssh-generic-qcom-msm8953.img bootstrap-prepared.img
   ```

   It asks three things, which the owner answers:
   - Wi-Fi name: empty means USB only; at most 32 bytes.
   - Wi-Fi password: empty means an open network; otherwise 8–63 printable ASCII characters, or 64 hex digits.
   - The bootstrap login password: 8 or more characters, at most 128 bytes, not `thinksmart`, typed twice.

   Passwords don't show while typed. On success the last line is `prepare: wrote bootstrap-prepared.img. Delete it after flashing: it may hold your WiFi password, and holds a hash of your login password.`. Use `bootstrap-prepared.img` as `<BOOTSTRAP_IMAGE>` below. Windows is untested: it needs Docker Desktop, and the script runs in WSL's bash.
3. Two reminders:
   - the bootstrap's SSH is open on the LAN until Ubuntu is flashed, so the login password must not be the published default (`prepare.sh` already refuses `thinksmart`);
   - after flashing this image (A8), delete `bootstrap-prepared.img`: it holds the Wi-Fi password and a hash of the login password.

Flash (`<BOOTSTRAP_IMAGE>` is `bootstrap-pmos-ssh-generic-qcom-msm8953.img` or `bootstrap-prepared.img`):

```bash
edl w system <BOOTSTRAP_IMAGE> 2>&1 | tee flash-bootstrap.log
edl reset
```

Expected output:

- the first command ends with `Wrote <BOOTSTRAP_IMAGE> to sector 923648.` (edl prints the name of the file you flashed)
- `edl reset` prints `Reset succeeded.`

The device reboots by itself: the lk2nd screen appears briefly, then postmarketOS starts. **Leave the USB cable in**; the next step uses it for SSH.

### A5. Log in to the bootstrap over SSH

Once booted, the bootstrap provides a network over the USB cable: the device is `172.16.42.1`, and the computer normally gets `172.16.42.2` automatically. If A4 used `prepare.sh` with a Wi-Fi name, it also joins that Wi-Fi. Try three ways in order: wait for the USB network (steps 1–4 below); if it doesn't appear within two minutes, use Wi-Fi; if neither works, connect a keyboard and join Wi-Fi by hand on the device.

Login password: if you used `prepare.sh`, the one you set there; if not, `thinksmart`, or the one you set in the "neither works" step below if you went through it.

**Wait for the USB network:**

1. Wait 1–2 minutes for the device to finish booting.
2. Check that the computer has a new network interface:
   - macOS: a new wired interface in "System Settings → Network";
   - Linux: a new `usb0` or `enx…` interface in `ip -br addr`;
   - Windows (untested): a new Ethernet adapter in "Network Connections". The bootstrap uses a USB NCM network adapter; Windows 11 has an NCM driver built in and usually recognizes it, while the NCM driver built into Windows 10 is incompatible with some devices and may not. If it isn't recognized, see "Windows can't use the USB network" below.
3. If the interface didn't get a `172.16.42.x` address, set it manually: IP `172.16.42.2`, subnet mask `255.255.0.0`, router empty.
4. Log in:

```bash
ping -c 3 172.16.42.1
ssh -o StrictHostKeyChecking=accept-new pmos@172.16.42.1
```

**No USB network within two minutes, and A4 used `prepare.sh` with a Wi-Fi name:** use Wi-Fi. Look for host name `thinksmarter` in the router's device list, or scan the LAN (the bootstrap only opens port 22):

```bash
nmap -p 22 --open <SUBNET>
ssh -o StrictHostKeyChecking=accept-new pmos@<BOOTSTRAP_IP>
```

**Neither works:** connect a USB keyboard and, in order:

1. Log in as `pmos` on the device's screen.
2. **If A4 didn't use `prepare.sh`, change the password and lock root before joining Wi-Fi.** Once on Wi-Fi, the bootstrap's SSH is open on the LAN, and in the upstream image both `pmos` and `root` have the published password `thinksmart`, with SSH accepting root password logins. Run the three lines below: the first sets your own password for `pmos` (8 or more characters, not `thinksmart`; it first asks for the current one, `thinksmart`), which A5 and A6 then use; the second locks `root`; the third checks the lock and should print one line starting with `root:!`:

   ```sh
   passwd
   doas passwd -l root
   doas grep '^root:!' /etc/shadow
   ```

   If it doesn't print that line, stop and don't join Wi-Fi.
3. Run the four lines below, join Wi-Fi in `nmtui`, then find the IP and log in as in "use Wi-Fi" above:

   ```sh
   doas sh -c 'dbus-uuidgen > /etc/machine-id'
   doas rc-service dbus start
   doas rc-service networkmanager start
   doas nmtui
   ```

After logging in, check that it's the right system:

```bash
cat /etc/hostname
ls /usr/local/sbin/apply-ubuntu-gpt.sh
```

Expected: `thinksmarter`, and the script path itself.

If it fails:

- No ping reply: check on the screen that postmarketOS is up; try another USB port; on macOS set the IP manually as in point 3; unplug and replug the USB cable.
- The screen stays on lk2nd (it says fastboot): the bootstrap wasn't flashed correctly; go back to A1, enter EDL, redo A4.
- Windows can't use the USB network (untested): add Wi-Fi with `prepare.sh` in A4 (Docker on Windows is untested), go back to A1, redo A4, then follow "use Wi-Fi" above; or borrow a macOS or Linux computer for this one step.
- SSH says the host key changed (you connected to `172.16.42.1` or this IP before): see [3.6](#36-ssh-says-the-host-key-changed).

### A6. Rewrite the partition table (ask the owner first, irreversible)

In the SSH session on the bootstrap, run:

```bash
sudo /usr/local/sbin/apply-ubuntu-gpt.sh
```

If `sudo` asks for a password, it's the one you logged in with in A5. Expected end of the output:

```
GPT rewrite complete.
Next steps:
1. Power off or reboot the device.
...
```

Step 3 of the script's message names upstream's image file; **ignore it**, the next step flashes this image.

Then power off right away:

```bash
sudo poweroff
```

This grows `system` to about 6.8 GB, deletes the stock vendor, cache, userdata and other partitions, and moves `persist` to the end of the disk.

If it fails: if the script reports an error, **don't power off and don't retry**; give the full output to the owner and stop.

### A7. Enter EDL again and check the new partition table

Wait until the screen goes black (with the cable in it may light up again by itself; that's fine), then unplug the power and enter EDL as in [1.1](#11-enter-edl-owner-does-this), then:

```bash
edl printgpt 2>&1 | tee gpt-after.txt
grep -E "^(system|userdata):" gpt-after.txt
```

Expected: a single `system:` line with `Length 0x00000001b3cfbe00`, and no `userdata:`.

If `system` is still `0x0000000060000000`: the partition table wasn't rewritten; go back to A4 (lk2nd is already in place, no need to redo A3).

### A8. Flash this image (ask the owner first)

```bash
edl w system thinksmart-ubuntu-<DATE>.img 2>&1 | tee flash-system.log
edl reset
```

- Writing takes from a few minutes to twenty; don't touch the cable.
- Expected: the output ends with `Wrote thinksmart-ubuntu-<DATE>.img to sector 923648.`, then `Reset succeeded.`

If it fails:

- `Error: … has N sectors but partition only has 3145728.`: the partition table is still stock; go back to A7 and check.
- Error halfway through: enter EDL again and retry once; if it still fails, stop and give `flash-system.log` to the owner.

When done, unplug the USB cable and go to [step 2: first boot](#2-first-boot-and-setup).

If A4 used `prepare.sh`, delete the prepared copy once this image has booted; it holds the Wi-Fi password and a hash of the login password:

```bash
rm ~/thinksmart/bootstrap-prepared.img
```

---

## Route B: device already runs this image or the upstream Ubuntu image

The partition table and lk2nd are already in place; only the `system` partition is rewritten.

> This wipes everything on the old system: chat history, the hub's API keys and admin password, Wi-Fi settings, SSH authorizations. To update just the voice client or the hub, **no reflash is needed**; see [section 5](#5-updates).

### B1. (Recommended) Back up user data first

If the old system is this image and you want to keep chat history and settings, back up as in [4.1](#41-back-up-before-flashing) and restore after flashing. If it's upstream's Plasma image, skip this; it has none of this data.

### B2. Enter EDL and check the partition table

Do [1.1](#11-enter-edl-owner-does-this) and [1.2](#12-read-the-partition-table), and check that the `system` Length is `0x00000001b3cfbe00`.

### B3. Flash this image (ask the owner first)

Exactly the same as [A8](#a8-flash-this-image-ask-the-owner-first):

```bash
edl w system thinksmart-ubuntu-<DATE>.img 2>&1 | tee flash-system.log
edl reset
```

Unplug the USB cable and go to step 2.

---

## 2. First boot and setup

### 2.1 First boot

- On first boot the screen first asks for the interface language (繁體中文 / 简体中文 / English); the welcome page comes after you tap one. You can change it later in the voice client's settings page.
- The first boot is slower, about 1–2 minutes: the system grows the root partition to fill the whole `system` partition and generates this device's own SSH host keys. Later boots take about 20 seconds.
- The screen shows the **welcome page** (dark background, with the device address and Wi-Fi status).

### 2.2 Connect Wi-Fi on the screen (owner does this)

1. On the welcome page tap the "Connect to Wi‑Fi" button, then tap your network in the "Choose Wi‑Fi" list.
2. Type the password with the on-screen keyboard and tap "Connect". When the panel shows "Connected to <WiFi name>" and goes back to the network list, it worked.
3. Tap the × at the top right to close the panel. The bottom of the welcome page shows "Device address", and a few seconds later the screen switches to the voice assistant.

Can't connect? See [3.3](#33-no-wi-fi-or-wi-fi-setup-on-the-screen-fails).

### 2.3 Find the device's IP address

You need it for the browser and SSH. The flashed system currently **can't be reached over a USB cable** (see the [appendix](#usb-network-after-flashing)); use its Wi-Fi address once it's on Wi-Fi.

AI agents: **find it yourself; don't ask the owner**.

1. Find the computer's subnet (the computer must be on the same router as the device):

   ```bash
   # macOS: prints this computer's IP
   ipconfig getifaddr $(route -n get default | awk '/interface:/{print $2}')
   # Linux: the address after src is this computer's IP
   ip -4 route get 1.1.1.1
   ```

   If this computer's IP is `192.168.1.23`, the subnet is usually `192.168.1.0/24`.

2. Scan the LAN for a machine with both port 22 (SSH) and 16688 (hub admin page) open:

   ```bash
   nmap -p 22,16688 --open 192.168.1.0/24
   ```

   No nmap: `brew install nmap` on macOS, `sudo apt install nmap` on Linux. If 16688 doesn't show up, the hub may still be loading its speech recognition model; wait a minute and scan again.

3. Confirm a candidate: open `http://<IP>:16688/admin` in a browser; if the tab title is "Xiaozhi Hub Admin" (in a Chinese browser, the Chinese title), it's the device. The command line prints the page's original title, which is the same Chinese text whatever your browser's language, `小智 Hub 管理后台`:

   ```bash
   curl -s http://<IP>:16688/admin | grep -o '<title>[^<]*'
   ```

If nmap finds nothing on macOS, or `curl` / `ssh` says `No route to host`: the terminal app lacks the "Local Network" permission; see [3.8](#38-ssh-says-no-route-to-host-on-macos).

Without nmap (works on Windows too; on Windows use `ipconfig` to see this computer's IP):

- the DHCP client list (device list) in your router's admin page; the host name is `thinksmart` (`thinksmarter` is the bootstrap's and the upstream image's host name);
- the device screen: "Device address" on the welcome page (after connecting to Wi-Fi the screen switches to the voice assistant almost at once, so it only flashes by), or "Device IP" in the voice interface's settings page. For this one, ask the owner to read the screen to you.

Below, `<DEVICE_IP>` stands for this address.

Before the first SSH: if this IP was used by another device or the old system before, clear the old entry first, or SSH will complain that the host key changed:

```bash
ssh-keygen -R <DEVICE_IP>
```

If you use the dedicated known-hosts file from section 4.2, clear it there too: `ssh-keygen -R <DEVICE_IP> -f ~/.ssh/known_hosts_thinksmart`.

### 2.4 Hub admin page: set the admin password, enter an API key (owner does this)

1. Open `http://<DEVICE_IP>:16688/admin` in a browser on the computer. After boot the hub needs about a minute to load its speech recognition model; if the page doesn't open, wait and reload.
2. **Set the admin password first.** Until then, anyone on the same network can open this page.
3. Enter the API key of your LLM provider. Claude API is the default; DeepSeek and other providers can be chosen in the admin page.
4. Save.

Without a key, the assistant wakes up but can't answer.

AI agents: the owner types the API key into the browser. Don't enter it for them, and don't write the key into any file or log.

### 2.5 Change the default passwords (do it right after flashing)

This image has one account that can log in, **with the default password `thinksmart`, reachable over SSH**; `root` is locked and can't log in:

| Account | Default password | Notes |
| --- | --- | --- |
| `ubuntu` | `thinksmart` | everyday account, passwordless sudo |

`ubuntu` uses `sudo` without a password on purpose: the update and backup scripts rely on it. So `ubuntu`'s password is in effect the device's administrator password, and anyone on the same network who knows the default can take full control. Change it:

```bash
ssh ubuntu@<DEVICE_IP>
passwd               # change ubuntu's password
```

If you have SSH'd to this device before (including `172.16.42.1` during the bootstrap), its host key has changed; clear the old entries first:

```bash
ssh-keygen -R <DEVICE_IP>
ssh-keygen -R 172.16.42.1
```

AI agents: the owner types the new password themselves. Don't make one up for them and don't record it.

### 2.6 Set the time zone

The image defaults to UTC. Over SSH, set your own time zone and check it:

```bash
sudo timedatectl set-timezone <TIME_ZONE>
timedatectl
```

Common ones: `America/Los_Angeles`, `Europe/London`, `Asia/Hong_Kong`. `timedatectl list-timezones` gives the full list. In the output of `timedatectl`, the `Time zone` line should show the zone you set.

### 2.7 Check that voice works (owner does this)

1. Say "**小麦小麦**" (*Xiǎo Mài Xiǎo Mài*; it also answers to "哈喽小麦" *Hā lou Xiǎo Mài* and "小麦同学" *Xiǎo Mài tóng xué*) to the device. The wake words are Chinese only. The screen switches to listening and a prompt sound plays.
2. Ask something in the speech language set in the hub admin page, and wait for the answer. To speak English, first set "Speech language" to English in the hub admin page; then ask, for example, "What day is it today?".

If it doesn't respond, check the services over SSH:

```bash
systemctl status thinksmart-client --no-pager | head -5    # voice client, should be active (running)
systemctl --user status xiaozhi-hub --no-pager | head -5   # hub, should be active (running)
journalctl -u thinksmart-client -b --no-pager | tail -30
```

Wakes up but can't answer: most likely the API key is missing or wrong; go back to 2.4. Doesn't wake up or no sound: see [3.4](#34-no-sound-or-no-reaction-to-the-wake-word).

---

## 3. Troubleshooting

### 3.1 edl can't find the device, or loses it right after connecting

Symptom: it stays at `Waiting for the device`, or reports `Couldn't detect the device`.

Try in this order:

1. Make sure the device really is in EDL: black screen, and the computer shows `9008` / `QUSB__BULK` (see 1.1).
2. Use another cable **that carries data**. Many cables only charge.
3. Plug straight into the computer, not a dock, hub or monitor port.
4. Unplug both the USB cable and the power cable to cut the power, then enter EDL again as in 1.1. EDL often needs re-entering after sitting idle for a while or after a failed command.
5. Linux: make sure ModemManager is stopped (`systemctl status ModemManager`) and the udev rules are installed; otherwise use `sudo`.
6. Windows (untested): if the device still has an exclamation mark in Device Manager, install WinUSB with Zadig as in 1.1. If Qualcomm's own 9008 driver is installed, edl can also use the serial port with `--serial` (`edl --serial printgpt`).
7. Apple Silicon Mac: make sure you clicked "Allow" for the accessory.

### 3.2 Boot stops at lk2nd's Fastboot screen

Symptom: the screen shows lk2nd's text menu with `Fastboot mode` and doesn't boot further.

Cause: lk2nd found nothing bootable on the `system` partition. Usually an interrupted write, the wrong file, or an image flashed before the partition table was rewritten.

What to do:

1. Unplug the power cable (you can't log in while it's stuck on lk2nd, so just unplug), then enter EDL as in 1.1.
2. Check with `edl printgpt` that `system` is `0x00000001b3cfbe00`.
3. Verify the `.img` again (section 0.5), then redo A8 / B3.

**Don't flash anything with fastboot.**

### 3.3 No Wi-Fi, or Wi-Fi setup on the screen fails

- The welcome page lists nearby networks. If yours isn't there, check that the router broadcasts normally on 2.4 GHz or 5 GHz (a hidden SSID has to be typed in).
- Right password but stuck at "Password accepted, getting a network address…": wait a minute; if it doesn't help, reboot the device once.
- The flashed system currently can't be reached over a USB cable (see the [appendix](#usb-network-after-flashing)). If Wi-Fi setup on the screen keeps failing: reboot the device and try again; if that doesn't help, reflash (A8 / B3) and set up Wi-Fi again.
- When you can already SSH in over Wi-Fi and want to switch to another network, connect from the command line:

  ```bash
  nmcli dev wifi list
  sudo nmcli dev wifi connect "<WIFI_NAME>" password "<WIFI_PASSWORD>"
  ip -4 -br addr show wlan0
  ```

  The text interface `sudo nmtui` works too.
- Connected but the screen still shows the welcome page: `sudo kiosk-mode restart` restarts the screen interface.

### 3.4 No sound, or no reaction to the wake word

```bash
systemctl --user status pipewire wireplumber thinksmart-mic --no-pager | grep -E "●|Active"
wpctl status | sed -n '/Audio/,/Video/p'
wpctl get-volume @DEFAULT_AUDIO_SINK@
```

- All three services should be `active (running)`. In `wpctl status`, Sinks should list `Built-in Audio Speaker`, and Sources `Microphone` and `Microphones (both)`.
- Too quiet: `wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5`, or use the device's volume buttons.
- The device's microphone switch (privacy switch) must be on; while it's off the assistant can't hear you.
- Services fine but still no sound: reboot the device. Its audio DSP occasionally gets stuck, and only a reboot brings it back.
- **Don't touch the sound card hardware directly** (`speaker-test -D hw:…`, `aplay -D hw:…` and the like): it can lock up the audio DSP. All sound goes through PipeWire.
- To restart WirePlumber on its own (after changing its configuration, say), stop the microphone service first and start it again afterwards. Otherwise the microphone service holds the capture device, WirePlumber can't find the sound card, and only a `Dummy Output` is left:

  ```bash
  systemctl --user stop thinksmart-mic && systemctl --user restart wireplumber && sleep 5 && systemctl --user start thinksmart-mic
  ```

  The voice client notices the sound dropped and restarts itself (about 20 seconds).

### 3.5 The screen never reaches the interface (black, white, or stuck on the welcome page)

```bash
systemctl status thinksmart-kiosk thinksmart-client --no-pager | grep -E "●|Active"
journalctl -u thinksmart-kiosk -b --no-pager | tail -30
```

- `thinksmart-kiosk` is the screen interface, `thinksmart-client` the voice client (which serves the interface).
- Restart the screen interface: `sudo kiosk-mode restart`.
- Stuck on the welcome page: the device isn't online or the voice client didn't start; see 3.3 and the `thinksmart-client` status above.
- Black screen but SSH works: the screen may have blanked; touch it or wave a hand in front of the device.
- SSH doesn't work either: the flashed system can't be reached over USB, so check that the device is on Wi-Fi (3.3) and that you have the right IP (2.3); for `No route to host` on macOS see 3.8; if nothing helps, reflash (A8 / B3).

### 3.6 SSH says the host key changed

```
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
```

Every flash generates new host keys, so this is expected:

```bash
ssh-keygen -R <DEVICE_IP>
ssh-keygen -R 172.16.42.1
```

If you see this warning **without** having reflashed, don't connect yet; check whether another device took over that IP.

### 3.7 Writing fails because the partition is too small

`Error: … has N sectors but partition only has 3145728.`: the partition table is still stock. Take route A and rewrite the partition table first.

### 3.8 ssh says No route to host on macOS

```
ssh: connect to host <DEVICE_IP> port 22: No route to host
```

The device is online and the IP is right, but the Mac can't reach LAN addresses: most likely the terminal app lacks the "Local Network" permission. Open "System Settings → Privacy & Security → Local Network", turn it on for the terminal app you use (Terminal, iTerm, VS Code…), then reopen the terminal and try again. If the browser can't open `http://<DEVICE_IP>:16688/admin`, it may be the same cause; turn the permission on for the browser.

### 3.9 Boot stops in emergency mode

What you see: a screen of text ending with `You are in emergency mode`, with `Failed to start systemd-fsck…` and `Dependency failed for boot.mount - /boot` above it, and further up `I/O error, dev mmcblk0 … (WRITE)`.

Why: the power was pulled without shutting down, the next boot had to repair the boot partition `/boot`, and writing the repair failed. Your data is on another partition (root) and is normally fine. Shutting down before unplugging (see [Things the owner must do by hand](#things-the-owner-must-do-by-hand)) avoids it.

Fix (rewrites only the boot partition, your data stays):

1. Enter EDL as in 1.1.
2. Read the whole `system` partition out first as a backup (about 6.8 GB; about 4 minutes here, up to 15 or so on a slower computer; don't touch the cable meanwhile):

   ```bash
   edl r system system-backup.img
   ```

3. Take the boot partition out of the image of **the version you flashed** (it starts at sector 2048 and is 509952 sectors long):

   ```bash
   dd if=thinksmart-ubuntu-<DATE>.img of=boot-part.img bs=512 skip=2048 count=509952
   ```

   On Windows run it in WSL.
4. Work out where to write it: the Offset of `system` in `edl printgpt` (for example `0x000000001c300000`) divided by 512, plus 2048. On a device whose partition table was changed as in this guide that is `923648 + 2048 = 925696`.
5. Write it (**ask the user first**) and restart:

   ```bash
   edl ws 925696 boot-part.img
   edl reset
   ```

   It should come up in the voice interface. If it still stops in emergency mode, keep a photo of the screen and `system-backup.img`, reflash with route B and restore your data as in 4.2 (without an earlier backup, the data can be recovered from `system-backup.img`).

---

## 4. Back up and restore user data

The image ships with no personal data. When reflashing from an older version of this image to a newer one, you can back these up first and restore them afterwards:

- the hub's data directory: API keys, admin password, Grok login, chat history `chat.db`;
- the Claude Code login (if installed);
- voice client settings: device ID, sleep hours, brightness, screen blanking;
- the screen interface's browser storage;
- `~/.ssh/authorized_keys`;
- Wi-Fi settings, host name, `/etc/thinksmart-kiosk.conf`;
- SSH host keys (optional; restoring them means computers won't warn about a changed host key).

These files contain API keys and passwords. Keep the backup on your own computer only; don't upload it.

### 4.1 Back up before flashing

On the computer, while the old system is still running and reachable over SSH:

```bash
ssh ubuntu@<DEVICE_IP> 'systemctl --user stop xiaozhi-hub; cd / && sudo tar --numeric-owner --ignore-failed-read -cpf - \
  home/ubuntu/xiaozhi-hub-server/main/xiaozhi-server/data home/ubuntu/.claude home/ubuntu/.claude.json \
  home/ubuntu/.config/thinksmart-client home/ubuntu/.local/share/thinksmart-kiosk home/ubuntu/.ssh \
  etc/NetworkManager/system-connections etc/netplan etc/thinksmart-kiosk.conf etc/hostname \
  etc/ssh/ssh_host_ecdsa_key etc/ssh/ssh_host_ecdsa_key.pub etc/ssh/ssh_host_ed25519_key \
  etc/ssh/ssh_host_ed25519_key.pub etc/ssh/ssh_host_rsa_key etc/ssh/ssh_host_rsa_key.pub; \
  systemctl --user start xiaozhi-hub' > userdata.tar
chmod 600 userdata.tar
tar tf userdata.tar | head -20
```

- The hub is stopped while packing so the chat database isn't caught mid-write; it starts again afterwards.
- Paths that don't exist are skipped with a one-line notice; the result is still fine.
- The last command should list paths such as `home/ubuntu/xiaozhi-hub-server/...` and `etc/NetworkManager/...`.

### 4.2 Restore after flashing

Prerequisites: flashed, Wi-Fi connected on the screen, `<DEVICE_IP>` known. The restore script is `image/restore-userdata.sh` in this repository and runs on macOS / Linux (on Windows use WSL).

1. Create a dedicated SSH key and authorize it on the device (asks once for `ubuntu`'s password, `thinksmart` right after flashing):

   ```bash
   [ -f ~/.ssh/thinksmart_ed25519 ] || ssh-keygen -t ed25519 -N '' -f ~/.ssh/thinksmart_ed25519
   ssh-copy-id -i ~/.ssh/thinksmart_ed25519 -o UserKnownHostsFile=~/.ssh/known_hosts_thinksmart ubuntu@<DEVICE_IP>
   ```

2. Restore:

   ```bash
   TS_HOST=<DEVICE_IP> image/restore-userdata.sh userdata.tar --host-keys
   ```

   - `--host-keys` also restores the old SSH host keys; leave it out if you don't want that. With it, the key recorded in step 1 is the new one and has to go: `ssh-keygen -R <DEVICE_IP> -f ~/.ssh/known_hosts_thinksmart`.
   - If step 1 warns that the host key changed (you connected to this IP before), run that `ssh-keygen -R` first, then redo step 1.
   - Expected output: first `restoring: …`, at the end `restored on the device` and `done; the hub needs about a minute to load its speech model`.
   - The script first unpacks the whole backup into a temporary directory on the device, and only when that fully succeeds stops the services and replaces files; if any step fails it exits with an error, the device stays as it was, and the services are started again.

3. After restoring, the hub's admin password and API keys are back as they were in the backup. The device password and the time zone aren't in the backup; when restoring onto a freshly flashed device, do 2.5 and 2.6 again.

---

## 5. Updates

- **Voice client**: check under "Software update" in the settings page and tap "Update" when a new version is available. Updates come from the Releases of [ohimsmart/oh-im-smart-client](https://github.com/ohimsmart/oh-im-smart-client). Updates are downloaded over HTTPS only, the size and sha256 of every file are checked before installing, and a broken install rolls back to the old version automatically.

  To publish client updates yourself (for example of your own modified client): generate the update manifest and packages with `update/make-release.py` from this repository, upload the files to a Release of your own GitHub repository, and change `SOURCES` in `/etc/thinksmart-update.conf` on the device to your repository's Release address. No keys are needed. Updates aren't signed, so whatever the update address serves is installed as root: put only addresses you control or trust in `SOURCES`, **never a public GitHub download mirror or proxy site**. Usage in `update/README.md`.
- **System layer** (kiosk shell, welcome page, screen keyboard, screen blanking and proximity, microphone service, audio and Bluetooth speaker configuration, the updater itself): shown in the same "Software update" card as the client; one tap installs the system layer first, then the client. Every file about to be replaced is backed up first; after installing, the services using them restart (the screen flickers once) and are checked, and the backup goes back if they don't come up. System layer packages are published in the same Release as the client (on the client repository); this repository's Releases only hold images to flash. Only the files listed in `image/system-files.txt` are replaced: the kernel, drivers, boot partition and apt packages are not (those need a reflash), and configuration you changed such as `/etc/thinksmart-kiosk.conf` is never overwritten.
- **Hub**: in the hub admin page (`http://<DEVICE_IP>:16688/admin`), click "Update gateway" in the sidebar; updates come from [ohimsmart/oh-im-smart-gateway](https://github.com/ohimsmart/oh-im-smart-gateway). The page shows the time and short commit hash of the current version and can check for a new one; it only installs when you click update, and a failed update rolls back automatically.

  From the command line instead, after SSH-ing into the device:

  ```bash
  cd ~/xiaozhi-hub-server && bash scripts/update.sh
  ```

  It pulls the new code, installs missing dependencies and restarts the hub.
- **System packages**: `sudo apt update && sudo apt upgrade` works as usual. The 41 packages the screen, sound and network depend on (patched Mesa, WebKitGTK, Weston, PipeWire, NetworkManager and others; list in `image/held-packages.txt`) are held at the tested versions and won't be upgraded. The kernel and drivers aren't managed by apt and don't change either.
- **The system image itself**: when a new image is released, reflash with [Route B](#route-b-device-already-runs-this-image-or-the-upstream-ubuntu-image), after a [4.1 backup](#41-back-up-before-flashing).

---

## Appendix: partitions and image layout

Background for people and AI agents who want to understand how it works.

| Partition | Purpose | Written by this guide? |
| --- | --- | --- |
| `boot` | lk2nd secondary bootloader | once, in route A |
| `system` | the whole Linux system, about 6.8 GB after the rewrite (starts at sector 923648, 14280671 sectors) | on every flash |
| `modem`, `dsp`, `persist` and others | Qualcomm firmware and device data | never |

The image (`.img`) is the content of the `system` partition and contains its own small MBR partition table:

- partition 1: `pmOS_boot` (ext2): kernel, initramfs, device tree, boot configuration;
- partition 2: `pmOS_root` (ext4): the Ubuntu 24.04 root file system. On first boot the initramfs grows it to the end of the `system` partition.

Boot order: Qualcomm PBL → stock SBL/aboot → lk2nd in the `boot` partition → extlinux configuration in `pmOS_boot` on `system` → Linux.

### USB network after flashing

**Known issue: the flashed system currently can't be reached over a USB cable.** The image's USB network is already set to NCM (device `172.16.42.1`; upstream's device package defaults to RNDIS, which macOS doesn't support), but once the system is up the device's USB port isn't recognized by the computer (it doesn't show up in the computer's USB device list), and switching back to RNDIS doesn't change that: the USB port doesn't come up in device mode. Not fixed yet.

So after flashing, connect the device to Wi-Fi and log in over its Wi-Fi address. The USB network during the bootstrap ([A5](#a5-log-in-to-the-bootstrap-over-ssh)) is not affected and works as described.

### System changes in this image

Compared with the upstream image, besides dropping the Plasma desktop and booting straight into the voice interface, these changes were made (all on purpose):

- No pinch zoom on the screen: the screen interface only takes the first finger, so a stray touch can't zoom the page.
- The USB network is set to NCM instead of upstream's RNDIS (though for now the flashed system's USB port isn't recognized by computers, see the previous section).
- Wi-Fi power save off: this QCA9379 adapter misses DHCP replies in power save, so after a boot it took 1–3 minutes to get an IP.
- 41 key packages held at their versions (see [section 5](#5-updates)).
- The proximity sensor is read directly from `/dev/i2c-0` (`ubuntu` is in the `i2c` group) instead of calling sudo every second and flooding the logs.
- Time sync uses five NTP servers, reachable both inside and outside China: `ntp.aliyun.com`, `ntp.tencent.com`, `cn.pool.ntp.org`, `pool.ntp.org`, `ntp.ubuntu.com`. The time zone defaults to UTC; see [2.6](#26-set-the-time-zone).
- The host name is `thinksmart`; `root` is locked and only `ubuntu` can log in (see [2.5](#25-change-the-default-passwords-do-it-right-after-flashing)).
- Logs live only in the systemd journal (persistent, at most 64 MB and one month); rsyslog, which wrote a second copy to `/var/log`, is off. Read logs with `journalctl`.
- No crash dumps (core dumps), to save disk space; zram compressed memory is on.
- ModemManager, avahi and udisks2, which aren't needed, are disabled.
- The on-screen keyboard is a system keyboard: the kiosk shell adds it to every page, and it slides up from the bottom of the screen when an input field is tapped (`kiosk/keyboard.js`). Pages use plain input fields and bring no keyboard of their own.
- On first boot the screen language is chosen first (繁體中文 / 简体中文 / English); until then the kiosk stays on the welcome page. Devices updated online from an older version (including ones showing their own web page) also stop once to choose. The choice is stored in `/home/ubuntu/.config/thinksmart-kiosk/lang`: the welcome page, the voice client (the shell adds `?lang=` when it opens the client on local port 8090) and the on-screen keyboard all follow it. Changing the language in the client's settings page writes the same file; the language button at the bottom of the welcome page chooses again.
- The voice client's settings page can switch Wi-Fi and the screen language too: the shell accepts these requests only from two kinds of page, the local welcome page and a kiosk address that is this device itself (127.0.0.1/localhost, the client by default). When the kiosk points at someone else's service it gets no such rights, and pages on the LAN can't reach them.
- Bluetooth speaker: only A2DP receiving is on (a phone plays music to it); hands-free (HFP/HSP) is off, so a phone won't route calls to it. The phone's sound doesn't go straight to the speaker: the voice client mixes it into its own output, so the wake word still works while music plays (`bluetooth/`). Pairing, the on/off switch and the phone list are in the client's settings page; pairing is only accepted for 3 minutes after tapping "+ Add a phone", with no PIN.

Known limitations:

- Wi-Fi can be set up on the screen without a network on first boot; speech recognition runs on the device, while the LLM and text-to-speech (Edge TTS by default) need the internet.
- The camera doesn't work (upstream is still researching it).
- The flashed system can't be reached over a USB cable, only over Wi-Fi (see [USB network after flashing](#usb-network-after-flashing)).
- To block pinch zoom the screen only takes the first finger. When typing fast on the on-screen keyboard with two alternating fingers, a second finger that lands before the first one lifts is dropped, losing a character. Type Wi-Fi passwords slowly, one finger at a time.
- The GPU, Wi-Fi and Bluetooth firmware in the image come from the same sources as upstream's (following upstream).
- While a phone plays music over Bluetooth, the voice client runs echo cancellation all the time, using about 70% of one core (about 20% without music). Wi-Fi and Bluetooth share one chip, so 2.4 GHz Wi-Fi may slow down while Bluetooth plays music.
- The phone shows the device with a tablet icon: BlueZ sets the device class from the machine type, and it can't be changed in `main.conf`.

---

## Credits and notices

- Oh I'm Smart is an extended version of [justhalfbit](https://github.com/justhalfbit)'s [thinksmart-ubuntu-image](https://github.com/justhalfbit/thinksmart-ubuntu-image), [xiaozhi-thinksmart-client](https://github.com/justhalfbit/xiaozhi-thinksmart-client) and [xiaozhi-hub-server](https://github.com/justhalfbit/xiaozhi-hub-server): the image, the voice client and the hub all start from them. Origins and licenses are in [NOTICE](NOTICE) and [LICENSE](LICENSE).
- The device port, lk2nd, the bootstrap image and the partitioning scheme come from [rickx/ubuntu-thinksmart](https://github.com/rickx/ubuntu-thinksmart); this project wouldn't exist without it. Upstream in turn credits FelixKa's postmarketOS device package and TAS5782M driver, and the postmarketOS project's kernel.
- The flashing tool is [bkerler/edl](https://github.com/bkerler/edl).
- The image is built from Ubuntu 24.04 packages. This is a personal project, not affiliated with Canonical, Lenovo or Qualcomm. "Ubuntu" and "ThinkSmart" are trademarks of their respective owners.
- Flashing is risky and can leave the device unable to boot. Make the full backup first; you do this at your own risk.

## What is in this repository

| Folder | Contents |
| --- | --- |
| `image/` | Building the image (capture from a device, clean, pack) and backing up / restoring user data |
| `bootstrap/` | Preparing the bootstrap image (`prepare.sh`: Wi-Fi, your own login password) |
| `tools/` | The check that the three tutorials agree (`check-readmes.sh`) |
| `kiosk/` | The kiosk shell (Weston + a full-screen WebKitGTK page), welcome page, on-screen keyboard, GPU watchdog, Wi-Fi power-save and NTP settings |
| `screen/` | Screen blanking, proximity and motion wake |
| `xiaozhi/` | The microphone service and audio configuration (ALSA, PipeWire, WirePlumber) |
| `bluetooth/` | Bluetooth speaker: WirePlumber configuration (A2DP receiving only, the phone's sound handed to the voice client) and BlueZ settings |
| `update/` | Online updates (voice client and system layer) |
| `mesa/` | Build script and patches of the patched Mesa (GPU white screen and hang fixes) |
| `codec-dmic/`, `kernel/` | Driver and device-tree patch for the second microphone, and the kernel environment it is built in |
| `zram/` | Compressed memory (zram) |

This repository is released under the MIT license, see [LICENSE](LICENSE).
