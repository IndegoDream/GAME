@echo off
rem Quest / PC VR: turn on the headset (Quest Link, Air Link, Virtual Desktop or SteamVR), then double-click this.
rem If the headset is not found the game just opens flat as normal.
start "" "%~dp0DungeonCrawlElite.exe" --vr --xr-mode on
