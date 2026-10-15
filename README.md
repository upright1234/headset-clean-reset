# Headset Clean Reset

Is your USB headset's mic dead on Windows? Maybe it works on console but not PC, or it worked yesterday and now nothing. Did the only fix you found say "uninstall everything from Device Manager and start over"?

This does that for you in about a minute. It removes your headset from Windows completely, **including the hidden leftover copies Device Manager doesn't show**. Then Windows installs it fresh, like the first time you plugged it in.

Built for (and tested on) the **Astro A50** PC-mode mic problem. It's designed to work with any USB headset or USB wireless dongle/base station: Astro, SteelSeries Arctis, HyperX, Corsair, Logitech, Razer, and others.

## How to use

1. **Download:** click the green **Code** button at the top of this page, then **Download ZIP**.
2. **Extract:** right-click the ZIP and choose **Extract All**. (It won't work from inside the ZIP.)
3. **Run:** double-click **`Reset-Headset.bat`**.
   - If Windows warns you about running a downloaded file, choose **Run** (or **More info**, then **Run anyway**).
4. Click **Yes** when Windows asks for admin permission.
5. **Pick your headset** from the list. Check the list of what will be removed, then type **Y**.
6. **Unplug** the headset (or its base station / USB dongle) when it tells you to, then press Enter.
7. **Plug it back in** when it tells you to. Done!

## After the reset: pick your mic again

Windows now sees your headset as a brand-new device. Open the apps you talk in and select the headset's microphone again:

- Discord: **User Settings, then Voice & Video, then Input Device**
- SteelSeries Sonar / GG: **Sonar, then Microphone, then select the headset mic**
- OBS, your game's voice settings, etc.
- Windows: **Settings, then System, then Sound, then Input**

## What it does (and doesn't do)

**It does:**
- Find every Windows entry for your headset: the USB device, its audio and control parts, and the speaker/microphone entries. It finds both the connected ones and the leftover "ghost" copies from older installs.
- Remove them with `pnputil`, the tool built into Windows. It's the same thing as "Uninstall device" in Device Manager, done for every entry at once.

**It doesn't:**
- Uninstall apps (Astro Command Center, G HUB, SteelSeries GG, etc.) or change their settings.
- Delete driver files. Windows reinstalls the headset automatically.
- Touch your other devices. It only removes devices from your headset's brand that have audio, so a mouse or keyboard from the same brand is left alone. If you own two audio devices from the same brand (say a Logitech headset and a Logitech webcam), both will show up in the list. That's why it always shows you the list and asks before removing anything.

## For advanced users

From PowerShell:

```powershell
.\Reset-Headset.ps1                  # pick from a list
.\Reset-Headset.ps1 -DryRun          # only show what would be removed, change nothing
.\Reset-Headset.ps1 -VendorId 9886   # skip the menu (9886 = Astro)
```

Each run saves a log to `%TEMP%\headset-clean-reset-log.txt`.

## Notes

- Needs **Windows 10 (version 2004 or newer) or Windows 11**.
- **USB** headsets and USB wireless dongles/base stations only. Bluetooth isn't supported.
- **Astro A50 owners:** each time it's plugged in, the base station briefly shows up as a second device and then switches back. So a couple of "leftover" entries reappear right after the reset. That's normal and harmless.

## License

[MIT](LICENSE): free to use, share, and change.
