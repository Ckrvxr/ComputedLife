# ComputedLife

This is a **personal Windows lock screen script** written in PowerShell. It continuously locks your screen during specified time periods to help people with weak self-discipline and poor time management avoid staying up late. I searched almost the entire internet for Windows lock screen tools but couldn't find anything suitable, so I wrote this script myself. The script is not overly forceful in non-lock periods (you can close it normally), but **it is nearly impossible to bypass during lock periods** (especially with hard drive encryption enabled). The script is lightweight, has no network connectivity, no tracking features, and is optimized for daily use with excellent compatibility. My goal was simplicity, free of charge, and effectiveness during lock periods. Date-based locking features haven't been extensively tested; if you encounter any issues, feel free to report them, and reasonable requests will be considered for fixes and improvements.

---

Most settings (a few are hardcoded, such as lock period reminders) are in Config.json, which you can modify and extend following the existing data structure. Usage is simple: configure Config.json, then right-click and run Install.bat as administrator to install. To uninstall, right-click and run Uninstall.bat as administrator. The script does not create any garbage files on your hard drive during execution. If you accidentally set up a permanent lock, you can enter PE system or safe mode to remove the startup entry. Also, make sure to keep your hard drive encryption key safe. If you can't enter safe mode or PE mode, and you don't have your hard drive encryption key, you will be locked out for good.

---

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)


This project is open source under the **Apache License 2.0**. You are free to use, modify, and distribute this code, but you must retain the original copyright notice. This software is provided "AS IS" without any express or implied warranties.

**This means that the system-level locking operations involved in this program mean that running it represents your acceptance of all risk disclaimers.**

---

Future plans include developing a full-featured, aesthetically pleasing Electron GUI lock screen application with analysis features, quiz-based unlock challenges, and convenient operation, synchronized across platforms (macOS and Windows).