<div align="center">

<img src="assets/icon.png" width="128" height="128" alt="Stuprator's Server icon">

# Stuprator's Server

**The optional Windows Tor connector for ERRATA**

<sub>A horror world that branches sideways, up and down. Twenty slots. Always night.</sub>

<br>

[![Download](https://img.shields.io/badge/Download-Install--Stuprators--Server.cmd-8b0000?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/SummusStuprator/stuprators-server-installer/releases/latest)

![Version](https://img.shields.io/badge/version-3.1.1-1a1a1a?style=flat-square)
![Platform](https://img.shields.io/badge/Windows-10%20%7C%2011-1a1a1a?style=flat-square)
![Java](https://img.shields.io/badge/Java-1.21.11-1a1a1a?style=flat-square)
![Bedrock](https://img.shields.io/badge/Bedrock-supported-1a1a1a?style=flat-square)
![Admin](https://img.shields.io/badge/admin%20rights-not%20needed-1a1a1a?style=flat-square)

</div>

---

## Join without installing anything

You don't need this installer to play. These addresses work in any normal Minecraft client:

| Edition | Address | Port |
|---|---|---|
| **Java** (1.21.11 recommended) | `stuprator.minecraft.party` | default |
| Java, fallback | `wap-conclusions.tun.ply.gg` | `55066` |
| **Bedrock** (experimental) | `wap-crop.tun.ply.gg` | `19132` |

The installer is for players who want to connect **through Tor**. On Java, the Tor route also delivers the
optional flashlight shader pack privately, over Tor.

## Install

1. Download **`Install-Stuprators-Server.cmd`** from the [latest release](https://github.com/SummusStuprator/stuprators-server-installer/releases/latest).
2. Double-click it. If Windows SmartScreen warns you, choose **More info → Run anyway**.
3. Pick **Java** or **Bedrock** in the window that opens.
4. Keep the app running while you play. It sits in the tray, and **Stuprator's Server** appears in your server list.

On first join, type `/register <password> <password>`. On later visits, type `/login <password>`.
Use a password you don't use anywhere else.

## What it actually does

The installer is a single plain-text file. Every line can be read before you run it.

```
 Install-Stuprators-Server.cmd
 ├─ batch header ──► copies the C# source below it to a temp file
 ├─ csc.exe ───────► compiles it with the .NET Framework already built into Windows
 └─ installer ─────► downloads Tor from torproject.org, checks its SHA-256, installs per-user
```

* **Downloads one thing:** the official Tor Expert Bundle from `torproject.org`. It refuses the file if a single byte
  differs from the pinned SHA-256 fingerprint.
* **Listens only on your own PC,** at the private loopback address `127.66.6.66`: Java on `25565`, Bedrock on `19160`.
  Bedrock's UDP is wrapped into a Tor stream. If a port is busy, it picks the next one and updates your server list.
* **No admin rights.** It installs into your user folder. The one optional exception is a loopback exemption for the
  old Microsoft Store version of Bedrock, which the installer explains and asks about first.
* **Clean removal** from *Settings → Apps → Installed apps → Stuprator's Server → Uninstall*.

## Verify the download

Compare the file's hash with [`dist/SHA256.txt`](dist/SHA256.txt) and the checksum attached to the release:

```powershell
Get-FileHash .\Install-Stuprators-Server.cmd -Algorithm SHA256
```

```
543ec049e493babdfe37f1fd17b4c5670748da8b5bb94ec9523a536c8cef4a58
```

## Build it yourself

```powershell
.\make.ps1
```

`make.ps1` joins [`src/header.cmd`](src/header.cmd) and [`src/StupratorsServer.cs`](src/StupratorsServer.cs) into
`dist/Install-Stuprators-Server.cmd`. It also compiles the program once as a check and rewrites `dist/SHA256.txt`.
The file has to stay plain ASCII, because the `more` command the batch header uses mangles anything else.

## Tor address

```
uni44ahkigjlamxnzh3njygylrvew6nnnr2z6w6yqanb23eydyzr4wyd.onion
```

Port `25565` is Java. Ports `19132` and `19133` carry Bedrock's signaling and relay. The installer handles all of this for you.

<div align="center">
<br>
<sub>Stuprator's Server · keep your light fed · don't stand still above the white</sub>
</div>
