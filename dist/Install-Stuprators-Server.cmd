@echo off
rem ==========================================================================
rem  STUPRATOR'S SERVER - INSTALLER  (one file, every line readable)
rem
rem  What happens when you double-click this file:
rem    1. The program source code written further down in THIS file (after the
rem       line "//===== PROGRAM SOURCE =====") is copied to a temporary file.
rem    2. It is compiled on your PC by the C# compiler that is part of
rem       Windows itself (.NET Framework 4.8). Nothing is downloaded for this.
rem    3. The compiled program opens an install window with simple options.
rem
rem  The program downloads exactly one thing: Tor, the official program from
rem  the Tor Project (torproject.org). It checks the download against a fixed
rem  SHA-256 fingerprint and refuses to use it if a single byte differs.
rem
rem  No admin rights, except one optional step for the old Microsoft Store
rem  version of Bedrock Edition, which the installer explains and asks about.
rem  Installs into your user folder. Remove it any time in
rem  Settings > Apps > Installed apps > Stuprator's Server > Uninstall.
rem
rem  Want a second opinion? Upload this file to ChatGPT, Claude or another AI
rem  and ask: "Is this installer safe? What exactly does it do?"
rem ==========================================================================
setlocal
title Stuprator's Server setup
echo Preparing the Stuprator's Server installer, one moment...
set "WORK=%TEMP%\StupratorsServerSetup"
if exist "%WORK%" rmdir /s /q "%WORK%"
mkdir "%WORK%" || goto :failed
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (
  echo This PC is missing the .NET Framework that normally comes with Windows 10 and 11.
  pause
  exit /b 1
)
set "LINE="
for /f "usebackq delims=:" %%a in (`findstr /n /b /c:"//===== PROGRAM SOURCE =====" "%~f0"`) do set "LINE=%%a"
if not defined LINE goto :failed
more +%LINE% "%~f0" > "%WORK%\StupratorsServer.cs"
"%CSC%" /nologo /target:winexe /optimize+ /out:"%WORK%\Stuprators Server.exe" /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:Microsoft.CSharp.dll "%WORK%\StupratorsServer.cs" > "%WORK%\build-log.txt" 2>&1
if errorlevel 1 goto :failed
start "" "%WORK%\Stuprators Server.exe" --setup-from "%~f0"
exit /b 0

:failed
echo.
echo Something went wrong while preparing the installer.
echo Details are in: %WORK%\build-log.txt
echo Please send that file to the server admin.
pause
exit /b 1

rem ==========================================================================
rem  Everything below is the C# program (the installer and the app itself).
rem ==========================================================================
//===== PROGRAM SOURCE =====
// ==========================================================================
// Stuprator's Server - installer and app (one C# file, C# 5 / .NET 4.8)
//
// The same program does three jobs, chosen by how it is started:
//   * Installer   - started by "Install Stuprator's Server.cmd" (or with --setup)
//   * App         - the installed copy. Runs Tor and connects Minecraft to the
//                   server. Lives in the tray if "start automatically" is on.
//   * Uninstaller - started with --uninstall (Settings > Apps uses this)
//
// Network activity, all of it:
//   1. Installer only: downloads the Tor Expert Bundle from torproject.org and
//      checks its SHA-256 fingerprint (TorArchiveSha256 below).
//   2. App: starts tor.exe, which connects to the Tor network.
//   3. App: listens on 127.66.6.66, a private address of your own PC (no other
//      computer can reach it), and forwards Minecraft's
//      connection through Tor to the server's .onion address. Nothing else.
//      Java Edition: TCP 127.66.6.66:25565 by default, with loopback port fallback.
//      Bedrock Edition (optional):
//      TCP + UDP 127.66.6.66:19160 (Bedrock's UDP is wrapped into a Tor stream).
//      (Any 127.x.x.x address means "this PC". Using 127.66.6.66 instead of the usual
//      127.0.0.1 avoids clashing with other programs, e.g. a local Minecraft server.)
//
// Files it writes:
//   %LOCALAPPDATA%\Programs\Stuprators Server\   program, tor.exe, icon
//   %LOCALAPPDATA%\Stuprators Server\            Tor cache, log file
//   Start menu / desktop shortcut, Settings > Apps entry, optional autostart
//   One "Stuprator's Server" entry in Minecraft's server lists (servers.dat for
//   Java, external_servers.txt for Bedrock), with a backup copy kept.
//   Bedrock (old Microsoft Store version only, and only if you agree): a
//   Windows "loopback exemption" so Minecraft may connect to this PC's own addresses.
// ==========================================================================

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: System.Reflection.AssemblyTitle("Stuprator's Server")]
[assembly: System.Reflection.AssemblyDescription("Connects Minecraft to Stuprator's Server through Tor")]
[assembly: System.Reflection.AssemblyProduct("Stuprator's Server")]
[assembly: System.Reflection.AssemblyCompany("Stuprator")]
[assembly: System.Reflection.AssemblyCopyright("Stuprator")]
[assembly: System.Reflection.AssemblyVersion("3.1.1.0")]
[assembly: System.Reflection.AssemblyFileVersion("3.1.1.0")]

namespace StupratorsServer
{
    static class Config
    {
        public const string AppName = "Stuprator's Server";
        public const string FolderName = "Stuprators Server";   // no apostrophe in file paths
        public const string Version = "3.1.1";
        public const string Publisher = "Stuprator";
        public const string Credit = "Made by SummusStuprator for his slaves";

        public const string ServerOnion = "uni44ahkigjlamxnzh3njygylrvew6nnnr2z6w6yqanb23eydyzr4wyd.onion";
        public const int ServerPort = 25565;
        public const int PreferredLocalPort = 25565;
        public const int JavaPortSearchCount = 50;
        // The app's own private address on the player's PC. Every 127.x.x.x address is
        // "this PC" on Windows; this one is unlikely to be used by anything else.
        public const string LocalAddress = "127.66.6.66";
        public static readonly IPAddress LocalIp = IPAddress.Parse(LocalAddress);
        // Addresses earlier versions wrote into server lists (migrated automatically).
        public static readonly string[] OldLocalAddresses = { "127.0.0.1", "127.0.0.1:25565" };
        public const string ServerListName = "Stuprator's Server";

        // Bedrock (via Geyser on the server): NetherNet signaling over TCP and
        // WebRTC over UDP. Both arrive at 127.66.6.66:19160 on the player's PC.
        public const int BedrockSignalingPort = 19132;   // onion port, TCP
        public const int BedrockRelayPort = 19133;       // onion port, UDP datagrams framed in TCP
        public const int BedrockLocalPort = 19160;       // what Bedrock players connect to
        public const string BedrockUwpFamily = "Microsoft.MinecraftUWP_8wekyb3d8bbwe";

        // Earlier releases were called "Stuprator's Server"; setup removes them.
        public const string LegacyUninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\CommunityMinecraft";
        public const string LegacyServerListName = "Community Minecraft";
        public const string JavaVersions = "Java Edition 1.8 to 1.20.4, or 1.21.5 and newer";
        public const string BedrockVersions = "Bedrock Edition for Windows, kept up to date";

        // Official Tor Expert Bundle. Hashes checked against the Tor Project's
        // OpenPGP signature (key EF6E286DDA85EA2A4BA7DE684E2C6E8793298290).
        public const string TorVersion = "16.0.1";
        public const string TorArchive = "tor-expert-bundle-windows-x86_64-16.0.1.tar.gz";
        public static readonly string[] TorUrls = {
            "https://dist.torproject.org/torbrowser/16.0.1/tor-expert-bundle-windows-x86_64-16.0.1.tar.gz",
            "https://archive.torproject.org/tor-package-archive/torbrowser/16.0.1/tor-expert-bundle-windows-x86_64-16.0.1.tar.gz"
        };
        public const string TorArchiveSha256 = "9eed3c3ff1fe43df034ce360196c9ec95472560d77ff55614d0cd5120edea27b";
        public const string TorExeSha256 = "da22856f95ee24f8ace4ad1ab04acbd818fd6c3042bc3cf8f1d7cc3fa3edcb2b";
        public const string GeoipSha256 = "5f0ebc505ad5a5b219f9c053ce6228c837669364349a1a70c236192dd99a1c3d";
        public const string Geoip6Sha256 = "d6bc775efb8f970afacbb702ea0c80dbf9e2add32232afcfe3f376a972503b56";

        static string Local { get { return Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData); } }
        public static string InstallDir { get { return Path.Combine(Local, "Programs", FolderName); } }
        public static string DataDir { get { return Path.Combine(Local, FolderName); } }
        public static string LogDir { get { return Path.Combine(DataDir, "logs"); } }
        public static string LogFile { get { return Path.Combine(LogDir, "stuprators-server.log"); } }
        public static string ExePath { get { return Path.Combine(InstallDir, FolderName + ".exe"); } }
        public static string TorExe { get { return Path.Combine(InstallDir, "tor", "tor.exe"); } }
        public static string GeoipFile { get { return Path.Combine(InstallDir, "data", "geoip"); } }
        public static string Geoip6File { get { return Path.Combine(InstallDir, "data", "geoip6"); } }
        public static string IconFile { get { return Path.Combine(InstallDir, "icon.ico"); } }
        public static string SourceCopy { get { return Path.Combine(InstallDir, "Install Stuprator's Server.cmd"); } }

        public const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        public const string RunValue = "StupratorsServer";
        public const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\StupratorsServer";
        public const string SettingsKey = @"Software\StupratorsServer";
        public const string MutexName = @"Local\StupratorsServer.App";
        public const string ShowEventName = @"Local\StupratorsServer.Show";
        public const string QuitEventName = @"Local\StupratorsServer.Quit";
    }

    static class Program
    {
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        static extern bool SetProcessDPIAware();

        [STAThread]
        static void Main(string[] args)
        {
            try { SetProcessDPIAware(); } catch { }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; // TLS 1.2

            string mode = args.Length > 0 ? args[0] : "";
            bool isInstalledCopy = Util.SamePath(Application.ExecutablePath, Config.ExePath);

            if (mode == "--uninstall")
            {
                Setup.UninstallInteractive(args.Contains("--quiet"));
                return;
            }
            if (mode == "--install-silent")
            {
                // Unattended install/repair with default options. Optional flags:
                // --no-autostart  --no-serverlists  --no-desktop  --no-java  --bedrock  --source <installer.cmd>
                var o = new SetupOptions
                {
                    Autostart = !args.Contains("--no-autostart"),
                    ServerLists = !args.Contains("--no-serverlists"),
                    Desktop = !args.Contains("--no-desktop"),
                    Java = !args.Contains("--no-java"),
                    Bedrock = args.Contains("--bedrock")
                };
                int si = Array.IndexOf(args, "--source");
                string src = si >= 0 && si + 1 < args.Length ? args[si + 1] : null;
                try { Setup.Install(o, src, false, s => Util.Log("setup: " + s), v => { }); Environment.Exit(0); }
                catch (Exception e) { Util.Log("Silent setup failed: " + e); Environment.Exit(1); }
                return;
            }
            if (mode == "--setup" || mode == "--setup-from" || !isInstalledCopy)
            {
                string source = mode == "--setup-from" && args.Length > 1 ? args[1] : null;
                Application.Run(new SetupForm(source));
                return;
            }

            bool created;
            using (var mutex = new Mutex(true, Config.MutexName, out created))
            {
                if (!created)
                {
                    // Already running: bring the existing window forward instead.
                    try { using (var ev = EventWaitHandle.OpenExisting(Config.ShowEventName)) ev.Set(); } catch { }
                    return;
                }
                // Record any unexpected error in the log (Help & fixes > Copy problem report includes it).
                Application.ThreadException += (s, e) => Util.Log("UNEXPECTED ERROR (UI): " + e.Exception);
                AppDomain.CurrentDomain.UnhandledException += (s, e) => Util.Log("UNEXPECTED ERROR (fatal): " + e.ExceptionObject);
                TaskScheduler.UnobservedTaskException += (s, e) => { Util.Log("Background task error: " + e.Exception.GetBaseException().Message); e.SetObserved(); };
                Util.Log("App started (version " + Config.Version + (mode == "--tray" ? ", in tray" : "") + ")");
                Application.Run(new AppForm(mode == "--tray"));
                Util.Log("App exited normally");
            }
        }
    }

    // ----------------------------------------------------------------------
    // Small helpers: hashing, logging, icon, registry, shortcuts
    // ----------------------------------------------------------------------
    static class Util
    {
        static readonly object logLock = new object();

        public static bool SamePath(string a, string b)
        {
            try { return string.Equals(Path.GetFullPath(a).TrimEnd('\\'), Path.GetFullPath(b).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase); }
            catch { return false; }
        }

        public static string Sha256(string file)
        {
            using (var sha = SHA256.Create())
            using (var s = File.OpenRead(file))
                return BitConverter.ToString(sha.ComputeHash(s)).Replace("-", "").ToLowerInvariant();
        }

        public static bool HashIs(string file, string expected)
        {
            try { return File.Exists(file) && Sha256(file) == expected; } catch { return false; }
        }

        public static bool TorFilesOk()
        {
            return HashIs(Config.TorExe, Config.TorExeSha256)
                && HashIs(Config.GeoipFile, Config.GeoipSha256)
                && HashIs(Config.Geoip6File, Config.Geoip6Sha256);
        }

        public static void Log(string line)
        {
            try
            {
                lock (logLock)
                {
                    Directory.CreateDirectory(Config.LogDir);
                    var fi = new FileInfo(Config.LogFile);
                    if (fi.Exists && fi.Length > 1024 * 1024)
                    {
                        string old = Config.LogFile + ".old";
                        if (File.Exists(old)) File.Delete(old);
                        File.Move(Config.LogFile, old);
                    }
                    File.AppendAllText(Config.LogFile, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + line + "\r\n");
                }
            }
            catch { }
        }

        public static string[] LogTail(int lines)
        {
            try
            {
                lock (logLock)
                {
                    if (!File.Exists(Config.LogFile)) return new string[0];
                    var all = File.ReadAllLines(Config.LogFile);
                    return all.Skip(Math.Max(0, all.Length - lines)).ToArray();
                }
            }
            catch { return new string[0]; }
        }

        // 64x64 pixel-art icon (the same image as the server icon). Each character is
        // one pixel; the palette maps each character to an RGB hex color.
        const int IconGrid = 64;
        static readonly string IconPalette =
            ".ae9a8d a99857a b987869 c80746c d8c685b e885d52 f716561 " +
            "g6a5955 h7a4d46 i5f4d4a j743a37 k5c3535 l494144 m3d363c " +
            "n422e32 o312d36 p751d22 q551e24 r3f2228 s40171d t2e252d " +
            "u26242f v271d26 w28161e x1e1e29 y1c1a25 z1b1923 A1a1620 " +
            "B171621 C15151f D19131d E15141d F14131b G12121e H121216 " +
            "I280e16 J110f16 K100e15 L0e0e16 M0e0e0f N0d0a12 O0b0c10 " +
            "P0a0a0e Q0a090c R0a070d S07080c T070707 U060608 V050508 " +
            "W050505 X040404 Y030305 Z030303 0020202 1010103 2010201 " +
            "3010101 4000101 5000001 6010100 7010000 8000000";
        static readonly string[] IconPixels = {
            "88888888888Yuiga.deeeehhnPUXMT0Q388XW88UU38SL888880MH08TZQOEEN08",
            "0388883ZX88YYVGmgdeeeehhnVT3TT0T0Q30UO1XY83LEW80MWZPCS0TUOKFFOZP",
            "Q88888TM08888OBLSldeeeego88888883T38NFY8880BBS80JOQQFV38UASWKQTM",
            "08888883880W4PVPGNlbddddmYW6383T3S38SS388SOFLS888MM8QY8TPRPWSPQ8",
            "8888888888TQ805YLyRgbdedlPQYQ83TVFYUUU188WYPOY83QQ0T8WZPFPMT88WQ",
            "8888888888TT3TZPJxGtbddflSUUQ888NO8HHM08030ZMS5ZQ83T8HWTHMZ0881H",
            "888888888888YQ83KCGMcddflRW5YPMUAOYNKU0Z3000T83QT3888MZ8XXQT3X8K",
            "8880838008WQ1S880SX0ibeilPVBumtEJKONLCS8888Z088ZM8888TX88QMTYT0M",
            "888PH08QX8838880KYW1maegguGtggoMQKYEBBV8883PX8883Y0888888QQ308YH",
            "806VQ0388888880HHEFSoaehllom.gt1MEEHGBBYWWZM83Z80HMZ8888883QT8TO",
            "8QX88TQ838838YM31TW8uahjigclltJ0FzFKEyBFVPQWZZP88ZX88888388838UM",
            "83888338W30T0Q0JBY3UgcghgaauNKHFBKHFEzLBEU68TX888803888Z08TP88WE",
            "88888888883ZYKGuxL1Olaaa.blMVHDAxKVEKKJOFKU83TM888TX888088TT883K",
            "88888888QT880OGBGLSNl..aflvWWFRyyKMJFNNFzJJP80K3883388MT8888888M",
            "88888888338YHFHGSJvl..gmlinPHHFF18HKJDJFAEOSP8Y883Q3W3WZ88888VQZ",
            "8888888888ZQYUXKNngcfigcdbgDHJKYNJGFAJNJFFNQQM8888W3MX8888ZQ8MA8",
            "0P388888888WVVVIiddmKvi.bbnHMHHyxuxDwvzzEEPY6T888888X38T38303KH8",
            "8X3888888WT1SNneadtGSSm.agJGFJvtvFwwwrrtxAVURRVPQ3X3888X88888vm8",
            "Q388YPY8VMNRIjb.gnNUMRDiamFyzttvzAnkniqqtzJPSKLVW3MW880WX8833My8",
            "XT33ztLUXSJnebdlDSW8HKLRgoGznnvrvueainhkktzDVUNY83Q08MWTX8888888",
            "88WwvouuMJndbhwSRU28SLGLooNonvrjkzhhhdjjknvzyFHMU8888HX888888338",
            "3YFnrwniihednRSFW658PzGGyAwnttkbfAhhbbdhknnExFO3MW38888888888888",
            "5SlnrigiigdtXY1NM388PCLGGLkntvlciRhea..ddkmxxFQ0MO38838888833888",
            "DvcafginllKQ358QK8888HGGGAnvxtttyveaba.abkouEH8XM3888888888ZM883",
            "ltl..itghfyN338MFXY3ZPCzLvtuxgglEibaintifeluEO88Q088888888880888",
            "gkiacnidioH8XX3KQMKYJCLLNnoomfclyta.dgiciggtJP888888888888888883",
            "keelmovwiA18XMVL8PR1HBBBLttuxlguEtebcccbcgitLK8888888QT888888888",
            "ikvozAskkV688ZKP1FKQHFBCLzmuAnlHEtddigfifgrtzK8888WZ8XW888888888",
            "gtoknjhrRY8883WHOHOKJSJBLxmoldavADrbbcdgfgvvO0888838833888888888",
            "fmieden5QQ88ZW8UHY0QKQEPSzmoo.bngcidbdagdgxyH88883W8888888888888",
            "elkderKRTQ88338HMT38MHFQOtioxacmc.abbabicfoGS888888888Z0888883MQ",
            "binrH8Y0ZZ8YY0PK0WMYKEFSPofiLnimfdddddllcglL8888888888X08888880T",
            "bewIQZ88888WT1EKM8VJKLFNFogfGwomb.lfdiBlfiiS88888888888888883MT8",
            "a.flN188888UFHJUTVSKFJPPtmlfzJHofamcflxgiffV8888088888888888YHZ8",
            "....D1888WMPEAPOUFOUSP1NommoBFNldhrlfzgagbfF8388W88888888Y8XHP88",
            "...al5U18YHHFHKVABP3KQ8zomoGLxGvlgggii.daactY33Z88888838WT83P088",
            ".aeggmMSPY0HEFNSOE1YFUYoommyyxGLSNzoogfaffamS80Q888888T0TW8T0888",
            "dgfailAAKOV1QKOzYHSKHQKmmmmxulxxzLLzxGFtJfcmNX888888WZ8ZX08MT883",
            "defvAvxFPNH83U1VUMEAKTAmmomoummuxuuEOKyECovEQT888888TX8TT8888888",
            "hnRmtJDCECL5883ZWWKWW8zlmumoBBxuuoF1TQwssqIwHS188888888Z08888888",
            "kImiARutJCGN85YQ8888QUvimouoGBCEzJ0Z0RrqqpppswDQ8288888QT8888888",
            "nooDAPEACGBGSJPY51YXPEymouxuyBL71JKPLNNMRIIqqqswMQ01388888888888",
            "HgmLGGGAvzuxCBBEGJSSKFHxozFAHHP0FDHzyDIsIDDDIssstwPUZ8888XX88833",
            "DiuGLBBFvvtoxyxuuuAHDPzxFADLFxzJzvvoovsppqwwDIsqsqwR1558800888TT",
            "tAFByCBBGxoouuotnlimBJFHFvvwwwvzAAvzvttsjppswIIssqqsMV1888888833",
            "yzABxBBzzyooxutrnkgimmoELykqrnnnkkrrssknqpppqrrrssqqqwMW58888888",
            "AFJzxxtxxyGDtoniigcdfiuuAnkknqkhhhkqqjbhkppppqsrrssrqqwO18888888",
            "ztFGBBxxxBytliiffccccgvtwrrnkqjdjkjkjkeekjppjpssqssssqsHPU88WM8Q",
            "ooHFxGBGGyFtffcccccfcccfinkhjkjjjkjkqqkkjhjppppssqsqqkqwzFVXPT0H",
            "ttEAuyooBmuocaaaaccffcgfgtkjjjdjjjkkkqh.djdjpppqqsssqkqswAEQPYZS",
            "tEEEzuullmumcaaaacccbcGvtvkjjheejhjd.ee..eedjpppqqswskqsrwvHVUTX",
            "vCzzAHuugfifcaacaaaa.ixnrrkkkjqjhhhe.gqgeeehhpppppqwwqqqsswvM3Z8",
            "oLxzFFxoogfcaaaabaaaalIrrrkkkjjjhhhejjdjjhhjhjpppppqnsqqqqwvwQU5",
            "muyywADuoGolfaaaaaa.afovzmkkjjjhehhdedeedehhheeppppjkwrqqqqqvzK6",
            "moNAwAvzuFFwAufaaccaaccvStkihjillgeeheehedaeedgqpppjqIvqqqkpqstM",
            "vvAJHNRJDDEJNGGmloxulgfoLAkheeegebbddedddbaehbgIqppjjsDrqqqpqsrw",
            "xzEMQQUUQJGLRzBGGxxGNLGGtntnnikkjehededddehehalNsqqrpkwtrqqqpqqs",
            "1XJV5QS11SGLBxyBxtuyyBBtgmLxGolsIkjkedbbbbbhd.zVDIsKppqvurqqppqq",
            "80PBGV8OBzGGyxyGyuoxxxCtclGuoulikskhhdaa.bhc.fDYMKJPqppsJvqqppqq",
            "1JSURY8OyyGCxyLuuooyyyGCgiGmmtgcdhkjeb.affcacmU8XT38IpqqIKvqsqqq",
            "5NL5888OCCLGxxGyuutvtvGygeAmguafcbekqhila.accD138883QqpqqKHvsssq",
            "80088Q1QLGSGuyBBvtttotBBgbto.li.c.cgggc..ba.dNPM8880PsqqqwQKwsss",
            "88888MWTFLVxuyovtnotuxCBfanva.g..a.abfabba..gIMH0885SIqqqsIRRIss",
            "88888X2ZYSNxuyvtnouBGByyf.guf.ah.f..hbabbb.arsIHJQ88SNsqkswHYWTI",
        };

        // Draws the pixel-art icon at any size (nearest-neighbour, crisp pixels).
        // Kept as text above so this single source file needs no image files.
        public static Bitmap DrawIcon(int size)
        {
            var colors = new Dictionary<char, Color>();
            foreach (string token in IconPalette.Split(' '))
                colors[token[0]] = Color.FromArgb(Convert.ToInt32(token.Substring(1), 16) | unchecked((int)0xFF000000));
            var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                float cell = size / (float)IconGrid;
                for (int y = 0; y < IconGrid; y++)
                    for (int x = 0; x < IconGrid; x++)
                        using (var brush = new SolidBrush(colors[IconPixels[y][x]]))
                            g.FillRectangle(brush, (float)Math.Floor(x * cell), (float)Math.Floor(y * cell),
                                (float)Math.Ceiling(cell) + 1, (float)Math.Ceiling(cell) + 1);
            }
            return bmp;
        }

        static Icon cachedIcon;
        public static Icon AppIcon()
        {
            if (cachedIcon == null)
            {
                using (var bmp = DrawIcon(64)) cachedIcon = Icon.FromHandle(bmp.GetHicon());
            }
            return cachedIcon;
        }

        // Writes a standard .ico file (PNG images inside) for shortcuts and Settings > Apps.
        public static void WriteIcoFile(string path)
        {
            int[] sizes = { 16, 32, 48, 256 };
            var pngs = new List<byte[]>();
            foreach (int s in sizes)
                using (var bmp = DrawIcon(s))
                using (var ms = new MemoryStream()) { bmp.Save(ms, ImageFormat.Png); pngs.Add(ms.ToArray()); }
            using (var f = new BinaryWriter(File.Create(path)))
            {
                f.Write((short)0); f.Write((short)1); f.Write((short)sizes.Length);
                int offset = 6 + 16 * sizes.Length;
                for (int i = 0; i < sizes.Length; i++)
                {
                    f.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i]));
                    f.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i]));
                    f.Write((byte)0); f.Write((byte)0);
                    f.Write((short)1); f.Write((short)32);
                    f.Write(pngs[i].Length); f.Write(offset);
                    offset += pngs[i].Length;
                }
                foreach (var png in pngs) f.Write(png);
            }
        }

        public static bool AutostartEnabled()
        {
            using (var k = Registry.CurrentUser.OpenSubKey(Config.RunKey))
                return k != null && k.GetValue(Config.RunValue) != null;
        }

        public static void SetAutostart(bool on)
        {
            using (var k = Registry.CurrentUser.CreateSubKey(Config.RunKey))
            {
                if (on) k.SetValue(Config.RunValue, "\"" + Config.ExePath + "\" --tray");
                else if (k.GetValue(Config.RunValue) != null) k.DeleteValue(Config.RunValue);
            }
        }

        public static bool GetSetting(string name, bool fallback)
        {
            using (var k = Registry.CurrentUser.OpenSubKey(Config.SettingsKey))
            {
                object v = k == null ? null : k.GetValue(name);
                return v == null ? fallback : Convert.ToInt32(v) != 0;
            }
        }

        public static void SetSetting(string name, bool value)
        {
            using (var k = Registry.CurrentUser.CreateSubKey(Config.SettingsKey))
                k.SetValue(name, value ? 1 : 0, RegistryValueKind.DWord);
        }

        public static string StartMenuShortcut
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), Config.AppName + ".lnk"); }
        }

        public static string DesktopShortcut
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), Config.AppName + ".lnk"); }
        }

        public static void CreateShortcut(string lnkPath, string description)
        {
            Type shellType = Type.GetTypeFromProgID("WScript.Shell");
            dynamic shell = Activator.CreateInstance(shellType);
            dynamic lnk = shell.CreateShortcut(lnkPath);
            lnk.TargetPath = Config.ExePath;
            lnk.WorkingDirectory = Config.InstallDir;
            lnk.IconLocation = Config.IconFile + ",0";
            lnk.Description = description;
            lnk.Save();
        }

        public static void DeleteFile(string path)
        {
            try { if (File.Exists(path)) File.Delete(path); } catch { }
        }

        public static void OpenFolder(string dir)
        {
            try { Directory.CreateDirectory(dir); Process.Start("explorer.exe", "\"" + dir + "\""); } catch { }
        }

        public static void OpenInNotepad(string file)
        {
            try { Process.Start("notepad.exe", "\"" + file + "\""); } catch { }
        }
    }

    // ----------------------------------------------------------------------
    // Install / repair / change / uninstall
    // ----------------------------------------------------------------------
    class SetupOptions
    {
        public bool Autostart = true;
        public bool ServerLists = true;
        public bool Desktop = true;
        public bool Java = true;
        public bool Bedrock = false;
        public bool GrantLoopback = false;   // only asked for the old Microsoft Store Bedrock
    }

    // Which Minecraft editions are on this PC.
    // For testing, STUPRATOR_SIMULATE=java,bedrock,uwp (any mix, or "none") replaces detection.
    static class Editions
    {
        static string Local { get { return Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData); } }
        static string Roaming { get { return Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData); } }
        static string Sim { get { return Environment.GetEnvironmentVariable("STUPRATOR_SIMULATE"); } }
        static bool Simulated(string what) { return Sim != null && Sim.Split(',').Select(x => x.Trim()).Contains(what); }

        public static bool JavaFound()
        {
            if (Sim != null) return Simulated("java");
            if (ServerLists.FindGameFolders().Count > 0) return true;
            string pf86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
            return File.Exists(Path.Combine(pf86, "Minecraft Launcher", "MinecraftLauncher.exe"))
                || Directory.Exists(Path.Combine(Local, "Packages", "Microsoft.4297127D64EC6_8wekyb3d8bbwe"));
        }

        public static bool BedrockFound()
        {
            if (Sim != null) return Simulated("bedrock") || Simulated("uwp");
            return UwpInstalled() || GdkInstalled() || Directory.Exists(Path.Combine(Roaming, "Minecraft Bedrock"));
        }

        static bool UwpInstalled()
        {
            return Directory.Exists(Path.Combine(Local, "Packages", Config.BedrockUwpFamily));
        }

        // The current PC version installs through the Xbox app as a normal Windows program.
        static bool GdkInstalled()
        {
            foreach (var d in DriveInfo.GetDrives())
            {
                try
                {
                    if (d.DriveType == DriveType.Fixed && d.IsReady &&
                        Directory.Exists(Path.Combine(d.RootDirectory.FullName, "XboxGames", "Minecraft for Windows")))
                        return true;
                }
                catch { }
            }
            return false;
        }

        // The old Microsoft Store (UWP) version runs in a sandbox that may not connect to
        // 127.0.0.1 until Windows grants it a "loopback exemption", which needs admin rights.
        public static bool LoopbackExemptionNeeded()
        {
            if (Sim != null) return Simulated("uwp");
            if (!UwpInstalled() || GdkInstalled()) return false;
            return !LoopbackExemptionPresent();
        }

        static bool LoopbackExemptionPresent()
        {
            try
            {
                var info = new ProcessStartInfo("CheckNetIsolation.exe", "LoopbackExempt -s");
                info.UseShellExecute = false;
                info.CreateNoWindow = true;
                info.RedirectStandardOutput = true;
                using (var p = Process.Start(info))
                {
                    string output = p.StandardOutput.ReadToEnd();
                    p.WaitForExit(10000);
                    return output.IndexOf(Config.BedrockUwpFamily, StringComparison.OrdinalIgnoreCase) >= 0;
                }
            }
            catch { return false; }
        }

        // Shows the Windows admin (UAC) prompt. Returns false if the player says no.
        public static bool SetLoopbackExemption(bool add)
        {
            try
            {
                var info = new ProcessStartInfo("CheckNetIsolation.exe",
                    "LoopbackExempt " + (add ? "-a" : "-d") + " -n=" + Config.BedrockUwpFamily);
                info.Verb = "runas";
                info.UseShellExecute = true;
                info.WindowStyle = ProcessWindowStyle.Hidden;
                using (var p = Process.Start(info))
                {
                    p.WaitForExit(60000);
                    Util.Log("Loopback exemption " + (add ? "added" : "removed") + ", exit code " + p.ExitCode);
                    return p.ExitCode == 0;
                }
            }
            catch (Exception e)
            {
                Util.Log("Loopback exemption not changed: " + e.Message);
                return false;
            }
        }
    }

    static class Setup
    {
        public static bool IsInstalled()
        {
            using (var k = Registry.CurrentUser.OpenSubKey(Config.UninstallKey))
                return k != null && File.Exists(Config.ExePath);
        }

        public static SetupOptions CurrentOptions()
        {
            var o = new SetupOptions();
            if (IsInstalled())
            {
                o.Autostart = Util.AutostartEnabled();
                o.ServerLists = Util.GetSetting("AddToServerLists", true);
                o.Desktop = File.Exists(Util.DesktopShortcut);
                o.Java = Util.GetSetting("Java", true);
                o.Bedrock = Util.GetSetting("Bedrock", false);
            }
            else
            {
                bool java = Editions.JavaFound(), bedrock = Editions.BedrockFound();
                o.Java = java || !bedrock;      // nothing found: assume Java, the player can change it
                o.Bedrock = bedrock;
            }
            return o;
        }

        // Asks a running copy of the app to quit, then makes sure it is gone,
        // so its files can be replaced or removed.
        public static void StopRunningApp(Action<string> say)
        {
            try
            {
                using (var ev = EventWaitHandle.OpenExisting(Config.QuitEventName))
                {
                    say("Closing the running Stuprator's Server app...");
                    ev.Set();
                }
            }
            catch { }
            int self = Process.GetCurrentProcess().Id;
            for (int i = 0; i < 50; i++)
            {
                bool any = false;
                var candidates = Process.GetProcessesByName(Config.FolderName).Concat(Process.GetProcessesByName("tor"));
                foreach (var p in candidates)
                {
                    if (p.Id == self) continue;
                    string file = null;
                    try { file = p.MainModule.FileName; } catch { }
                    if (file == null) continue;
                    if (Util.SamePath(file, Config.ExePath) || Util.SamePath(file, Config.TorExe))
                    {
                        any = true;
                        if (i >= 30) try { p.Kill(); } catch { }
                    }
                }
                if (!any) return;
                Thread.Sleep(100);
            }
        }

        public static List<string> Install(SetupOptions o, string sourceCmd, bool forceTorDownload, Action<string> say, Action<int> progress)
        {
            if (!Environment.Is64BitOperatingSystem)
                throw new Exception("Stuprator's Server needs 64-bit Windows (Tor is only provided as a 64-bit program).");
            StopRunningApp(say);
            RemoveLegacyInstall(say);
            Directory.CreateDirectory(Config.InstallDir);
            Directory.CreateDirectory(Config.DataDir);
            Util.Log("Setup started (version " + Config.Version + ")");

            if (!Util.SamePath(Application.ExecutablePath, Config.ExePath))
            {
                say("Copying the program...");
                File.Copy(Application.ExecutablePath, Config.ExePath, true);
            }
            if (sourceCmd != null && File.Exists(sourceCmd) && !Util.SamePath(sourceCmd, Config.SourceCopy))
                File.Copy(sourceCmd, Config.SourceCopy, true);

            // Register the uninstaller first, so even a half-finished install can be removed from Settings > Apps.
            say("Adding Stuprator's Server to Settings > Apps...");
            Util.WriteIcoFile(Config.IconFile);
            RegisterUninstaller();

            if (forceTorDownload || !Util.TorFilesOk())
                InstallTor(say, progress);
            else
                say("Tor is already installed and its fingerprint matches.");
            progress(100);

            say("Creating shortcuts...");
            Util.CreateShortcut(Util.StartMenuShortcut, "Join Stuprator's Server");
            if (o.Desktop) Util.CreateShortcut(Util.DesktopShortcut, "Join Stuprator's Server");
            else Util.DeleteFile(Util.DesktopShortcut);

            Util.SetAutostart(o.Autostart);
            Util.SetSetting("AddToServerLists", o.ServerLists);
            Util.SetSetting("Java", o.Java);
            Util.SetSetting("Bedrock", o.Bedrock);

            var added = new List<string>();
            if (o.ServerLists && o.Java)
            {
                say("Adding the server to your Minecraft Java server lists...");
                added = ServerLists.AddEverywhere(say);
            }
            else ServerLists.RemoveEverywhere(say);
            if (o.ServerLists && o.Bedrock)
            {
                say("Adding the server to your Minecraft Bedrock server list...");
                int n = BedrockLists.AddEverywhere();
                if (n > 0) added.Add("Bedrock Edition");
            }
            else BedrockLists.RemoveEverywhere();

            if (o.Bedrock && o.GrantLoopback)
            {
                say("Asking Windows to let Minecraft Bedrock connect to this PC (admin prompt)...");
                bool granted = Editions.SetLoopbackExemption(true);
                if (granted) Util.SetSetting("AddedLoopback", true);
                say(granted ? "Done: Minecraft Bedrock may now connect to this PC's own addresses."
                            : "Skipped: you said no to the admin prompt. You can do it later from the Help tab.");
            }
            Util.Log("Setup finished. Java=" + o.Java + " Bedrock=" + o.Bedrock + " Autostart=" + o.Autostart +
                " ServerLists=" + o.ServerLists + " Desktop=" + o.Desktop);
            return added;
        }

        // Earlier releases were called "Community Minecraft". Remove them quietly with
        // their own uninstaller so nobody ends up with two copies.
        static void RemoveLegacyInstall(Action<string> say)
        {
            string cmd;
            using (var k = Registry.CurrentUser.OpenSubKey(Config.LegacyUninstallKey))
            {
                if (k == null) return;
                cmd = k.GetValue("QuietUninstallString") as string;
            }
            say("Removing the older \"Community Minecraft\" version...");
            try
            {
                if (cmd != null && cmd.StartsWith("\""))
                {
                    int q = cmd.IndexOf('"', 1);
                    string exe = cmd.Substring(1, q - 1), args = cmd.Substring(q + 1).Trim();
                    if (File.Exists(exe))
                        using (var p = Process.Start(new ProcessStartInfo(exe, args) { UseShellExecute = false }))
                            p.WaitForExit(60000);
                }
            }
            catch (Exception e) { Util.Log("Legacy uninstall problem: " + e.Message); }
            try { Registry.CurrentUser.DeleteSubKeyTree(Config.LegacyUninstallKey, false); } catch { }
        }

        static void InstallTor(Action<string> say, Action<int> progress)
        {
            string downloadDir = Path.Combine(Config.DataDir, "download");
            Directory.CreateDirectory(downloadDir);
            string archive = Path.Combine(downloadDir, Config.TorArchive);
            Exception last = null;
            bool ok = false;
            foreach (string url in Config.TorUrls)
            {
                try
                {
                    say("Downloading Tor " + Config.TorVersion + " from " + new Uri(url).Host + "...");
                    Download(url, archive, progress);
                    say("Checking the download's fingerprint...");
                    string got = Util.Sha256(archive);
                    if (got != Config.TorArchiveSha256)
                        throw new Exception("The download's fingerprint is wrong (" + got.Substring(0, 16) + "...). It was NOT used.");
                    ok = true;
                    break;
                }
                catch (Exception e)
                {
                    last = e;
                    Util.Log("Tor download from " + url + " failed: " + e.Message);
                    Util.DeleteFile(archive);
                }
            }
            if (!ok) throw new Exception("Could not download Tor. " + (last == null ? "" : last.Message));

            say("Fingerprint matches the official Tor release. Unpacking...");
            var wanted = new Dictionary<string, string>();
            wanted["tor/tor.exe"] = Config.TorExe;
            wanted["data/geoip"] = Config.GeoipFile;
            wanted["data/geoip6"] = Config.Geoip6File;
            Tar.ExtractSome(archive, wanted);
            Util.DeleteFile(archive);
            if (!Util.TorFilesOk()) throw new Exception("The unpacked Tor files do not match their fingerprints.");
            say("Tor installed and verified.");
        }

        static void Download(string url, string target, Action<int> progress)
        {
            var req = (HttpWebRequest)WebRequest.Create(url);
            req.UserAgent = "StupratorsServerInstaller/" + Config.Version;
            req.Timeout = 30000;
            req.ReadWriteTimeout = 60000;
            using (var resp = (HttpWebResponse)req.GetResponse())
            using (var input = resp.GetResponseStream())
            using (var output = File.Create(target))
            {
                long total = resp.ContentLength, done = 0;
                byte[] buf = new byte[81920];
                int n;
                while ((n = input.Read(buf, 0, buf.Length)) > 0)
                {
                    output.Write(buf, 0, n);
                    done += n;
                    if (done > 64L * 1024 * 1024) throw new Exception("The download is far larger than Tor should be. It was stopped.");
                    if (total > 0) progress((int)(done * 100 / total));
                }
            }
        }

        static void RegisterUninstaller()
        {
            using (var k = Registry.CurrentUser.CreateSubKey(Config.UninstallKey))
            {
                k.SetValue("DisplayName", Config.AppName);
                k.SetValue("DisplayVersion", Config.Version);
                k.SetValue("Publisher", Config.Publisher);
                k.SetValue("DisplayIcon", Config.IconFile);
                k.SetValue("InstallLocation", Config.InstallDir);
                k.SetValue("UninstallString", "\"" + Config.ExePath + "\" --uninstall");
                k.SetValue("QuietUninstallString", "\"" + Config.ExePath + "\" --uninstall --quiet");
                k.SetValue("ModifyPath", "\"" + Config.ExePath + "\" --setup");
                k.SetValue("Comments", "Connects Minecraft to the Stuprator's Server server through Tor.");
                k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                k.SetValue("EstimatedSize", 12000, RegistryValueKind.DWord);
                k.SetValue("InstallDate", DateTime.Now.ToString("yyyyMMdd"));
            }
        }

        public static void UninstallInteractive(bool quiet)
        {
            if (!quiet)
            {
                var answer = MessageBox.Show(
                    "Remove Stuprator's Server from this PC?\n\n" +
                    "This removes the program, Tor, the shortcuts, the autostart entry and the server-list entry it added.\n" +
                    "Your Minecraft worlds, settings and accounts are not touched.",
                    "Uninstall Stuprator's Server", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                if (answer != DialogResult.Yes) return;
            }
            try
            {
                Uninstall(delegate(string s) { }, !quiet);
                if (!quiet)
                    MessageBox.Show("Stuprator's Server was removed.", "Uninstall Stuprator's Server", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception e)
            {
                if (!quiet)
                    MessageBox.Show("Some parts could not be removed:\n" + e.Message, "Uninstall Stuprator's Server", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        // mayPrompt: allowed to show the admin prompt to undo the Bedrock loopback exemption.
        public static void Uninstall(Action<string> say, bool mayPrompt = false)
        {
            StopRunningApp(say);
            Util.SetAutostart(false);
            try { ServerLists.RemoveEverywhere(say); } catch { }
            try { BedrockLists.RemoveEverywhere(); } catch { }
            if (mayPrompt && Util.GetSetting("AddedLoopback", false))
            {
                MessageBox.Show("Windows will ask for admin permission once more, to undo the Bedrock connection permission this program added.",
                    "Uninstall Stuprator's Server", MessageBoxButtons.OK, MessageBoxIcon.Information);
                Editions.SetLoopbackExemption(false);
            }
            Util.DeleteFile(Util.StartMenuShortcut);
            Util.DeleteFile(Util.DesktopShortcut);
            try { Registry.CurrentUser.DeleteSubKeyTree(Config.UninstallKey, false); } catch { }
            try { Registry.CurrentUser.DeleteSubKeyTree(Config.SettingsKey, false); } catch { }
            try { if (Directory.Exists(Config.DataDir)) Directory.Delete(Config.DataDir, true); } catch { }

            // A running program cannot delete its own file, so a hidden command
            // removes the program folder two seconds after this program exits.
            if (Directory.Exists(Config.InstallDir))
            {
                // Retries every second for up to 2 minutes, so it still works if a "removed" message box stays open.
                string d = Config.InstallDir.Replace("\"", "");
                var info = new ProcessStartInfo("cmd.exe",
                    "/c for /l %i in (1,1,120) do (if exist \"" + d + "\" (rmdir /s /q \"" + d + "\" 2>nul & ping 127.0.0.1 -n 2 >nul))");
                info.CreateNoWindow = true;
                info.UseShellExecute = false;
                info.WorkingDirectory = Path.GetTempPath();
                Process.Start(info);
            }
        }
    }

    // Minimal reader for .tar.gz files: extracts only the named entries.
    static class Tar
    {
        public static void ExtractSome(string archive, Dictionary<string, string> wanted)
        {
            int found = 0;
            using (var file = File.OpenRead(archive))
            using (var gz = new GZipStream(file, CompressionMode.Decompress))
            {
                byte[] header = new byte[512];
                while (ReadFull(gz, header, 512))
                {
                    if (header.All(b => b == 0)) break;
                    string name = Ascii(header, 0, 100);
                    string prefix = Ascii(header, 345, 155);
                    if (prefix.Length > 0) name = prefix + "/" + name;
                    long size = Convert.ToInt64(Ascii(header, 124, 12).Trim().Length == 0 ? "0" : Ascii(header, 124, 12).Trim(), 8);
                    char type = (char)header[156];
                    long padded = (size + 511) / 512 * 512;
                    string target;
                    if ((type == '0' || type == '\0') && wanted.TryGetValue(name, out target))
                    {
                        Directory.CreateDirectory(Path.GetDirectoryName(target));
                        string tmp = target + ".partial";
                        using (var outFile = File.Create(tmp)) Copy(gz, outFile, size);
                        Skip(gz, padded - size);
                        if (File.Exists(target)) File.Delete(target);
                        File.Move(tmp, target);
                        found++;
                    }
                    else Skip(gz, padded);
                }
            }
            if (found != wanted.Count) throw new Exception("The Tor archive is missing expected files.");
        }

        static string Ascii(byte[] b, int start, int len)
        {
            int end = start;
            while (end < start + len && b[end] != 0) end++;
            return Encoding.ASCII.GetString(b, start, end - start);
        }

        static bool ReadFull(Stream s, byte[] buf, int n)
        {
            int got = 0;
            while (got < n)
            {
                int k = s.Read(buf, got, n - got);
                if (k <= 0) return false;
                got += k;
            }
            return true;
        }

        static void Copy(Stream from, Stream to, long n)
        {
            byte[] buf = new byte[81920];
            while (n > 0)
            {
                int k = from.Read(buf, 0, (int)Math.Min(buf.Length, n));
                if (k <= 0) throw new EndOfStreamException();
                to.Write(buf, 0, k);
                n -= k;
            }
        }

        static void Skip(Stream s, long n) { Copy(s, Stream.Null, n); }
    }

    // ----------------------------------------------------------------------
    // Minecraft server lists (servers.dat, NBT format) for common launchers
    // ----------------------------------------------------------------------
    static class ServerLists
    {
        const string BackupSuffix = ".before-stuprators-server";

        // Returns (launcher label, game folder) for every Minecraft folder found.
        public static List<KeyValuePair<string, string>> FindGameFolders()
        {
            var list = new List<KeyValuePair<string, string>>();
            string roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

            string official = Path.Combine(roaming, ".minecraft");
            if (Directory.Exists(official)) list.Add(new KeyValuePair<string, string>("Minecraft Launcher / TLauncher / other .minecraft launchers", official));

            // MultiMC-style launchers keep each instance in its own folder.
            foreach (var launcher in new[] { "PolyMC", "PrismLauncher", "MultiMC", "UltimMC", "FjordLauncher" })
                foreach (string inst in Subdirs(Path.Combine(roaming, launcher, "instances")))
                {
                    string game = Path.Combine(inst, ".minecraft");
                    if (!Directory.Exists(game)) game = Path.Combine(inst, "minecraft");
                    if (Directory.Exists(game)) list.Add(new KeyValuePair<string, string>(launcher + ": " + Path.GetFileName(inst), game));
                }
            foreach (string inst in Subdirs(Path.Combine(roaming, "ModrinthApp", "profiles")))
                list.Add(new KeyValuePair<string, string>("Modrinth App: " + Path.GetFileName(inst), inst));
            foreach (string inst in Subdirs(Path.Combine(roaming, "com.modrinth.theseus", "profiles")))
                list.Add(new KeyValuePair<string, string>("Modrinth App: " + Path.GetFileName(inst), inst));
            foreach (string inst in Subdirs(Path.Combine(home, "curseforge", "minecraft", "Instances")))
                list.Add(new KeyValuePair<string, string>("CurseForge: " + Path.GetFileName(inst), inst));
            foreach (string inst in Subdirs(Path.Combine(roaming, "ATLauncher", "instances")))
                list.Add(new KeyValuePair<string, string>("ATLauncher: " + Path.GetFileName(inst), inst));
            foreach (string inst in Subdirs(Path.Combine(roaming, "gdlauncher_carbon", "data", "instances")))
            {
                string game = Path.Combine(inst, "instance");
                if (Directory.Exists(game)) list.Add(new KeyValuePair<string, string>("GDLauncher: " + Path.GetFileName(inst), game));
            }
            foreach (string inst in Subdirs(Path.Combine(roaming, "gdlauncher_next", "instances")))
                list.Add(new KeyValuePair<string, string>("GDLauncher: " + Path.GetFileName(inst), inst));
            return list;
        }

        static IEnumerable<string> Subdirs(string dir)
        {
            try { return Directory.Exists(dir) ? Directory.GetDirectories(dir) : new string[0]; }
            catch { return new string[0]; }
        }

        public static List<string> AddEverywhere(Action<string> say)
        {
            var done = new List<string>();
            foreach (var place in FindGameFolders())
            {
                try
                {
                    if (Add(Path.Combine(place.Value, "servers.dat"))) Util.Log("Server list updated: " + place.Value);
                    done.Add(place.Key);
                }
                catch (Exception e) { Util.Log("Could not update " + place.Value + ": " + e.Message); }
            }
            return done;
        }

        public static void RemoveEverywhere(Action<string> say)
        {
            foreach (var place in FindGameFolders())
            {
                try { Remove(Path.Combine(place.Value, "servers.dat")); }
                catch (Exception e) { Util.Log("Could not clean " + place.Value + ": " + e.Message); }
            }
        }

        static bool IsOurs(Nbt entry)
        {
            string name = entry.GetString("name"), ip = entry.GetString("ip");
            if (ip == null || (name != Config.ServerListName && name != Config.LegacyServerListName)) return false;
            if (ip == Config.LocalAddress || Config.OldLocalAddresses.Contains(ip)) return true;
            return IsJavaPortAddress(ip, Config.LocalAddress)
                || (name == Config.ServerListName && IsJavaPortAddress(ip, "127.0.0.1"));
        }

        static bool IsJavaPortAddress(string address, string host)
        {
            int port;
            return address.StartsWith(host + ":", StringComparison.Ordinal)
                && int.TryParse(address.Substring(host.Length + 1), NumberStyles.None, CultureInfo.InvariantCulture, out port)
                && port >= Config.PreferredLocalPort && port < Config.PreferredLocalPort + Config.JavaPortSearchCount;
        }

        // Adds the server at the top of the list, or updates our existing entry's name and
        // address. Returns false if nothing needed to change.
        public static bool Add(string file, string address = null)
        {
            address = address ?? Config.LocalAddress;
            Nbt root = Load(file);
            List<Nbt> servers = ServersList(root);
            var existing = servers.FirstOrDefault(IsOurs);
            if (existing != null)
            {
                if (existing.GetString("ip") == address && existing.GetString("name") == Config.ServerListName) return false;
                existing.Set("ip", Nbt.String(address));
                existing.Set("name", Nbt.String(Config.ServerListName));
                Save(file, root);
                return true;
            }
            if (File.Exists(file) && !File.Exists(file + BackupSuffix)) File.Copy(file, file + BackupSuffix);
            var entry = Nbt.Compound();
            entry.Set("ip", Nbt.String(address));
            entry.Set("name", Nbt.String(Config.ServerListName));
            servers.Insert(0, entry);
            Save(file, root);
            return true;
        }

        public static void UpdateExisting(string address)
        {
            foreach (var place in FindGameFolders())
            {
                string file = Path.Combine(place.Value, "servers.dat");
                try
                {
                    if (!File.Exists(file)) continue;
                    Nbt root = Load(file);
                    if (ServersList(root).Any(IsOurs)) Add(file, address);
                }
                catch (Exception e) { Util.Log("Could not update " + file + ": " + e.Message); }
            }
        }

        public static void Remove(string file)
        {
            if (!File.Exists(file)) return;
            Nbt root = Load(file);
            List<Nbt> servers = ServersList(root);
            int before = servers.Count;
            servers.RemoveAll(IsOurs);
            if (servers.Count == before) return;
            bool hadOriginal = File.Exists(file + BackupSuffix);
            if (!hadOriginal && servers.Count == 0 && root.Fields.Count == 1)
                File.Delete(file);                         // we created this file; leave no trace
            else
                Save(file, root);
            Util.DeleteFile(file + BackupSuffix);          // our entry is gone, the backup is no longer needed
        }

        static Nbt Load(string file)
        {
            if (!File.Exists(file) || new FileInfo(file).Length == 0) return Nbt.Compound();
            using (var s = File.OpenRead(file))
            {
                Stream input = s;
                int first = s.ReadByte(), second = s.ReadByte();
                s.Position = 0;
                if (first == 0x1f && second == 0x8b) input = new GZipStream(s, CompressionMode.Decompress);
                var r = new BinaryReader(input);
                byte type = r.ReadByte();
                if (type != Nbt.TCompound) throw new InvalidDataException("servers.dat is not a compound");
                Nbt.ReadRawString(r);
                return Nbt.ReadPayload(r, type);
            }
        }

        static List<Nbt> ServersList(Nbt root)
        {
            Nbt list = root.Get("servers");
            if (list == null || list.Type != Nbt.TList)
            {
                list = Nbt.List(Nbt.TCompound);
                root.Set("servers", list);
            }
            if (list.Items.Count == 0) list.ElementType = Nbt.TCompound;
            return list.Items;
        }

        static void Save(string file, Nbt root)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(file));
            string tmp = file + ".tmp";
            using (var w = new BinaryWriter(File.Create(tmp)))
            {
                w.Write(Nbt.TCompound);
                Nbt.WriteRawString(w, new byte[0]);
                Nbt.WritePayload(w, root);
            }
            if (File.Exists(file)) File.Replace(tmp, file, null);
            else File.Move(tmp, file);
        }
    }

    // Bedrock Edition's server list: external_servers.txt, one server per line as
    // "index:name:address:port:unix-time". The Servers tab shows these.
    static class BedrockLists
    {
        const string BackupSuffix = ".before-stuprators-server";

        public static List<string> Files()
        {
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            var dirs = new List<string>();
            dirs.Add(Path.Combine(local, "Packages", Config.BedrockUwpFamily, "LocalState", "games", "com.mojang", "minecraftpe"));
            string users = Path.Combine(roaming, "Minecraft Bedrock", "Users");
            if (Directory.Exists(users))
                foreach (string user in Directory.GetDirectories(users))
                    dirs.Add(Path.Combine(user, "games", "com.mojang", "minecraftpe"));
            return dirs.Where(Directory.Exists).Select(d => Path.Combine(d, "external_servers.txt")).ToList();
        }

        static bool IsOurs(string line)
        {
            string[] f = line.Split(':');
            return f.Length >= 4 && (f[1] == Config.ServerListName || f[1] == Config.LegacyServerListName)
                && (f[2] == Config.LocalAddress || f[2] == "127.0.0.1") && f[3] == Config.BedrockLocalPort.ToString();
        }

        public static int AddEverywhere()
        {
            int added = 0;
            foreach (string file in Files())
            {
                try
                {
                    var lines = File.Exists(file) ? File.ReadAllLines(file).Where(l => l.Trim().Length > 0).ToList() : new List<string>();
                    string ours = lines.FirstOrDefault(IsOurs);
                    if (ours != null && ours.Split(':')[2] == Config.LocalAddress) { added++; continue; }
                    if (ours != null) lines.Remove(ours);      // old address: replace the entry below
                    if (File.Exists(file) && !File.Exists(file + BackupSuffix)) File.Copy(file, file + BackupSuffix);
                    int next = 1;
                    foreach (string l in lines) { int n; if (int.TryParse(l.Split(':')[0], out n) && n >= next) next = n + 1; }
                    long now = (long)(DateTime.UtcNow - new DateTime(1970, 1, 1)).TotalSeconds;
                    lines.Add(next + ":" + Config.ServerListName + ":" + Config.LocalAddress + ":" + Config.BedrockLocalPort + ":" + now);
                    File.WriteAllLines(file, lines);
                    Util.Log("Bedrock server list updated: " + file);
                    added++;
                }
                catch (Exception e) { Util.Log("Could not update " + file + ": " + e.Message); }
            }
            return added;
        }

        public static void RemoveEverywhere()
        {
            foreach (string file in Files())
            {
                try
                {
                    if (!File.Exists(file)) continue;
                    var lines = File.ReadAllLines(file).Where(l => l.Trim().Length > 0).ToList();
                    int before = lines.Count;
                    lines.RemoveAll(IsOurs);
                    if (lines.Count == before) continue;
                    if (lines.Count == 0 && !File.Exists(file + BackupSuffix)) File.Delete(file);
                    else File.WriteAllLines(file, lines);
                    Util.DeleteFile(file + BackupSuffix);
                }
                catch (Exception e) { Util.Log("Could not clean " + file + ": " + e.Message); }
            }
        }
    }

    // Generic NBT tag that keeps unknown data exactly as it was read.
    class Nbt
    {
        public const byte TEnd = 0, TByte = 1, TShort = 2, TInt = 3, TLong = 4, TFloat = 5, TDouble = 6,
            TByteArray = 7, TString = 8, TList = 9, TCompound = 10, TIntArray = 11, TLongArray = 12;

        public byte Type;
        public long Number;                                   // byte/short/int/long and raw float/double bits
        public byte[] Raw;                                    // string bytes or byte array
        public int[] Ints;
        public long[] Longs;
        public byte ElementType;                              // for lists
        public List<Nbt> Items = new List<Nbt>();             // for lists
        public List<KeyValuePair<byte[], Nbt>> Fields = new List<KeyValuePair<byte[], Nbt>>(); // for compounds

        public static Nbt Compound() { return new Nbt { Type = TCompound }; }
        public static Nbt List(byte element) { return new Nbt { Type = TList, ElementType = element }; }
        public static Nbt String(string s) { return new Nbt { Type = TString, Raw = Encoding.UTF8.GetBytes(s) }; }

        public Nbt Get(string name)
        {
            byte[] key = Encoding.UTF8.GetBytes(name);
            foreach (var f in Fields) if (f.Key.SequenceEqual(key)) return f.Value;
            return null;
        }

        public void Set(string name, Nbt value)
        {
            byte[] key = Encoding.UTF8.GetBytes(name);
            for (int i = 0; i < Fields.Count; i++)
                if (Fields[i].Key.SequenceEqual(key)) { Fields[i] = new KeyValuePair<byte[], Nbt>(key, value); return; }
            Fields.Add(new KeyValuePair<byte[], Nbt>(key, value));
        }

        public string GetString(string name)
        {
            Nbt t = Get(name);
            return t != null && t.Type == TString ? Encoding.UTF8.GetString(t.Raw) : null;
        }

        static byte[] Be(BinaryReader r, int n) { byte[] b = r.ReadBytes(n); if (b.Length != n) throw new EndOfStreamException(); Array.Reverse(b); return b; }
        static short I16(BinaryReader r) { return BitConverter.ToInt16(Be(r, 2), 0); }
        static int I32(BinaryReader r) { return BitConverter.ToInt32(Be(r, 4), 0); }
        static long I64(BinaryReader r) { return BitConverter.ToInt64(Be(r, 8), 0); }
        static void W(BinaryWriter w, byte[] b) { Array.Reverse(b); w.Write(b); }

        public static byte[] ReadRawString(BinaryReader r)
        {
            int len = (ushort)I16(r);
            return r.ReadBytes(len);
        }

        public static void WriteRawString(BinaryWriter w, byte[] s)
        {
            W(w, BitConverter.GetBytes((short)s.Length));
            w.Write(s);
        }

        public static Nbt ReadPayload(BinaryReader r, byte type)
        {
            var t = new Nbt { Type = type };
            switch (type)
            {
                case TByte: t.Number = r.ReadSByte(); break;
                case TShort: t.Number = I16(r); break;
                case TInt: case TFloat: t.Number = I32(r); break;
                case TLong: case TDouble: t.Number = I64(r); break;
                case TByteArray: t.Raw = r.ReadBytes(I32(r)); break;
                case TString: t.Raw = ReadRawString(r); break;
                case TList:
                    t.ElementType = r.ReadByte();
                    int count = I32(r);
                    for (int i = 0; i < count; i++) t.Items.Add(ReadPayload(r, t.ElementType));
                    break;
                case TCompound:
                    while (true)
                    {
                        byte ft = r.ReadByte();
                        if (ft == TEnd) break;
                        byte[] name = ReadRawString(r);
                        t.Fields.Add(new KeyValuePair<byte[], Nbt>(name, ReadPayload(r, ft)));
                    }
                    break;
                case TIntArray:
                    t.Ints = new int[I32(r)];
                    for (int i = 0; i < t.Ints.Length; i++) t.Ints[i] = I32(r);
                    break;
                case TLongArray:
                    t.Longs = new long[I32(r)];
                    for (int i = 0; i < t.Longs.Length; i++) t.Longs[i] = I64(r);
                    break;
                default: throw new InvalidDataException("Unknown NBT tag " + type);
            }
            return t;
        }

        public static void WritePayload(BinaryWriter w, Nbt t)
        {
            switch (t.Type)
            {
                case TByte: w.Write((sbyte)t.Number); break;
                case TShort: W(w, BitConverter.GetBytes((short)t.Number)); break;
                case TInt: case TFloat: W(w, BitConverter.GetBytes((int)t.Number)); break;
                case TLong: case TDouble: W(w, BitConverter.GetBytes(t.Number)); break;
                case TByteArray: W(w, BitConverter.GetBytes(t.Raw.Length)); w.Write(t.Raw); break;
                case TString: WriteRawString(w, t.Raw); break;
                case TList:
                    w.Write(t.Items.Count == 0 ? t.ElementType : t.Items[0].Type);
                    W(w, BitConverter.GetBytes(t.Items.Count));
                    foreach (var item in t.Items) WritePayload(w, item);
                    break;
                case TCompound:
                    foreach (var f in t.Fields)
                    {
                        w.Write(f.Value.Type);
                        WriteRawString(w, f.Key);
                        WritePayload(w, f.Value);
                    }
                    w.Write(TEnd);
                    break;
                case TIntArray:
                    W(w, BitConverter.GetBytes(t.Ints.Length));
                    foreach (int v in t.Ints) W(w, BitConverter.GetBytes(v));
                    break;
                case TLongArray:
                    W(w, BitConverter.GetBytes(t.Longs.Length));
                    foreach (long v in t.Longs) W(w, BitConverter.GetBytes(v));
                    break;
            }
        }
    }

    // ----------------------------------------------------------------------
    // UI helpers
    // ----------------------------------------------------------------------
    static class Ui
    {
        // Dark theme to match the artwork: near-black, bone-white text, blood-red accent.
        public static readonly Color Bg = Color.FromArgb(18, 14, 16);
        public static readonly Color Card = Color.FromArgb(30, 23, 26);
        public static readonly Color Card2 = Color.FromArgb(44, 34, 38);
        public static readonly Color Line = Color.FromArgb(64, 50, 54);
        public static readonly Color Ink = Color.FromArgb(238, 230, 222);
        public static readonly Color Muted = Color.FromArgb(166, 150, 144);
        public static readonly Color Accent = Color.FromArgb(178, 36, 26);
        public static readonly Color AccentHover = Color.FromArgb(206, 52, 38);
        public static readonly Color Green = Color.FromArgb(88, 204, 120);
        public static readonly Color Amber = Color.FromArgb(236, 176, 70);
        public static readonly Color Red = Color.FromArgb(240, 92, 80);

        public const string Check = "\u2714";
        public const string Bullet = "\u2022";
        public const string Arrow = "\u203A";

        public static Label Text(string text, float size = 10f, FontStyle style = FontStyle.Regular, Color? color = null)
        {
            var l = new Label();
            l.Text = text;
            l.AutoSize = true;
            l.Font = new Font(style.HasFlag(FontStyle.Bold) ? "Segoe UI Semibold" : "Segoe UI", size, style & ~FontStyle.Bold);
            l.ForeColor = color ?? Ink;
            l.BackColor = Color.Transparent;
            l.Margin = new Padding(0, 0, 0, 8);
            return l;
        }

        static void Flat(Button b, Color back, Color hover, Color fore)
        {
            b.FlatStyle = FlatStyle.Flat;
            b.FlatAppearance.BorderSize = 0;
            b.FlatAppearance.MouseOverBackColor = hover;
            b.FlatAppearance.MouseDownBackColor = hover;
            b.BackColor = back;
            b.ForeColor = fore;
            b.Cursor = Cursors.Hand;
            b.UseVisualStyleBackColor = false;
        }

        // primary: the one big obvious action on a screen.
        public static Button Button(string text, EventHandler click, bool primary = false)
        {
            var b = new Button();
            b.Text = text;
            b.AutoSize = true;
            b.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            b.Padding = primary ? new Padding(22, 9, 22, 9) : new Padding(14, 6, 14, 6);
            b.Margin = new Padding(0, 0, 10, 10);
            b.Font = new Font(primary ? "Segoe UI Semibold" : "Segoe UI", primary ? 12.5f : 10f);
            if (primary) Flat(b, Accent, AccentHover, Color.White);
            else Flat(b, Card2, Line, Ink);
            b.Click += click;
            return b;
        }

        // A wide primary button that fills the content width.
        public static Button Wide(Control owner, string text, EventHandler click)
        {
            var b = Button(text, click, true);
            b.AutoSize = false;
            b.Size = new Size(Scale(owner, 520), Scale(owner, 56));
            b.Font = new Font("Segoe UI Semibold", 14f);
            return b;
        }

        // A big choice tile: title + one line of explanation.
        public static Button Tile(Control owner, string title, string sub, EventHandler click)
        {
            var b = new Button();
            b.Text = title + "\n" + sub;
            b.TextAlign = ContentAlignment.MiddleLeft;
            b.Padding = new Padding(16, 0, 0, 0);
            b.Size = new Size(Scale(owner, 520), Scale(owner, 64));
            b.Margin = new Padding(0, 0, 0, 10);
            b.Font = new Font("Segoe UI Semibold", 12f);
            Flat(b, Card2, Line, Ink);
            b.FlatAppearance.BorderSize = 1;
            b.FlatAppearance.BorderColor = Line;
            b.Click += click;
            return b;
        }

        // Small text-only button for secondary choices ("Options", "Read the code").
        public static Button Link(string text, EventHandler click)
        {
            var b = new Button();
            b.Text = text;
            b.AutoSize = true;
            b.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            b.Font = new Font("Segoe UI", 9.5f, FontStyle.Underline);
            Flat(b, Bg, Bg, Muted);
            b.FlatAppearance.MouseOverBackColor = Card;
            b.Margin = new Padding(0, 0, 6, 0);
            b.Padding = new Padding(0);
            b.Click += click;
            return b;
        }

        public static CheckBox CheckBox(string text, bool on)
        {
            var c = new CheckBox();
            c.Text = text;
            c.Checked = on;
            c.AutoSize = true;
            c.Font = new Font("Segoe UI", 10.5f);
            c.ForeColor = Ink;
            c.Margin = new Padding(0, 4, 0, 8);
            return c;
        }

        public static FlowLayoutPanel Stack()
        {
            var p = new FlowLayoutPanel();
            p.FlowDirection = FlowDirection.TopDown;
            p.WrapContents = false;
            p.Dock = DockStyle.Fill;
            p.AutoScroll = true;
            p.BackColor = Bg;
            p.Padding = new Padding(28, 22, 28, 10);
            return p;
        }

        public static FlowLayoutPanel Row()
        {
            var p = new FlowLayoutPanel();
            p.FlowDirection = FlowDirection.LeftToRight;
            p.AutoSize = true;
            p.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            p.WrapContents = true;
            p.BackColor = Color.Transparent;
            p.Margin = new Padding(0, 4, 0, 4);
            return p;
        }

        // A rounded-looking card (flat panel) that stacks its children.
        public static FlowLayoutPanel CardPanel(Control owner)
        {
            var p = new FlowLayoutPanel();
            p.FlowDirection = FlowDirection.TopDown;
            p.WrapContents = false;
            p.AutoSize = true;
            p.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            p.BackColor = Card;
            p.Padding = new Padding(18, 14, 18, 8);
            p.Margin = new Padding(0, 0, 0, 14);
            p.MinimumSize = new Size(Scale(owner, 520), 0);
            return p;
        }

        public static ProgressBar Bar(Control owner)
        {
            return new ProgressBar { Width = Scale(owner, 484), Height = Scale(owner, 8), Margin = new Padding(0, 4, 0, 10) };
        }

        static float dpi;
        // Uses the screen's DPI (not the window's) so no window handle is created early.
        public static int Scale(Control c, int px)
        {
            if (dpi == 0) using (var g = Graphics.FromHwnd(IntPtr.Zero)) dpi = g.DpiX;
            return (int)(px * dpi / 96f);
        }

        public static void Wrap(Control parent, params Label[] labels)
        {
            foreach (var l in labels) l.MaximumSize = new Size(Scale(parent, 520), 0);
        }

        [System.Runtime.InteropServices.DllImport("dwmapi.dll")]
        static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        // Dark title bar on Windows 10 20H1+ and 11 (ignored elsewhere).
        public static void DarkTitleBar(Form f)
        {
            try { int on = 1; DwmSetWindowAttribute(f.Handle, 20, ref on, 4); } catch { }
        }

        // The header strip: icon, name, tagline.
        public static Panel Header(Form owner, string tagline, int height)
        {
            var banner = new Panel();
            banner.Dock = DockStyle.Top;
            banner.Height = Scale(owner, height);
            banner.BackColor = Color.FromArgb(10, 7, 8);
            int iconSize = Scale(owner, height - 20);
            var logo = new PictureBox();
            logo.Image = Util.DrawIcon(iconSize);
            logo.SizeMode = PictureBoxSizeMode.AutoSize;
            logo.Location = new Point(Scale(owner, 20), Scale(owner, 10));
            var title = Text(Config.AppName, 20f, FontStyle.Bold);
            title.Location = new Point(Scale(owner, 20) + iconSize + Scale(owner, 16), Scale(owner, height / 2 - 30));
            var sub = Text(tagline, 10.5f, FontStyle.Regular, Muted);
            sub.Location = new Point(Scale(owner, 20) + iconSize + Scale(owner, 18), Scale(owner, height / 2 + 8));
            var line = new Panel { Dock = DockStyle.Bottom, Height = Scale(owner, 3), BackColor = Accent };
            banner.Controls.Add(logo);
            banner.Controls.Add(title);
            banner.Controls.Add(sub);
            banner.Controls.Add(line);
            return banner;
        }

        public static Label Footer(Form owner)
        {
            var footer = Text(Config.Credit, 8.5f, FontStyle.Italic, Color.FromArgb(120, 104, 100));
            footer.AutoSize = false;
            footer.Dock = DockStyle.Bottom;
            footer.Height = Scale(owner, 28);
            footer.TextAlign = ContentAlignment.MiddleCenter;
            footer.BackColor = Color.FromArgb(10, 7, 8);
            return footer;
        }
    }

    // Finds and opens the player's Minecraft. For Java it picks the launcher they used most
    // recently (by its data folder); for Bedrock it uses the "minecraft:" link Windows provides.
    static class Launchers
    {
        public static bool Open(bool bedrock)
        {
            try
            {
                if (bedrock) { Process.Start("minecraft:"); return true; }
                string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                string pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
                string pf86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
                var candidates = new List<Tuple<string, string>>();   // (program or shortcut, data folder)
                Action<string, string> add = (exe, data) => { if (File.Exists(exe)) candidates.Add(Tuple.Create(exe, data)); };
                add(Path.Combine(pf86, "Minecraft Launcher", "MinecraftLauncher.exe"), Path.Combine(roaming, ".minecraft"));
                add(Path.Combine(local, "Programs", "PrismLauncher", "prismlauncher.exe"), Path.Combine(roaming, "PrismLauncher"));
                add(Path.Combine(pf, "PrismLauncher", "prismlauncher.exe"), Path.Combine(roaming, "PrismLauncher"));
                add(Path.Combine(local, "Programs", "PolyMC", "polymc.exe"), Path.Combine(roaming, "PolyMC"));
                add(Path.Combine(pf, "PolyMC", "polymc.exe"), Path.Combine(roaming, "PolyMC"));
                add(Path.Combine(local, "Programs", "MultiMC", "MultiMC.exe"), Path.Combine(roaming, "MultiMC"));
                // Any Start menu shortcut whose name looks like a Minecraft launcher.
                foreach (string menu in new[] { Environment.GetFolderPath(Environment.SpecialFolder.Programs), Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms) })
                {
                    try
                    {
                        foreach (string lnk in Directory.GetFiles(menu, "*.lnk", SearchOption.AllDirectories))
                            if (Regex.IsMatch(Path.GetFileName(lnk), "Minecraft Launcher|Prism|PolyMC|MultiMC|TLauncher|ATLauncher|SKLauncher|Modrinth|GDLauncher", RegexOptions.IgnoreCase))
                                candidates.Add(Tuple.Create(lnk, Path.Combine(roaming, ".minecraft")));
                    }
                    catch { }
                }
                string xboxLauncher = Path.Combine(local, "Packages", "Microsoft.4297127D64EC6_8wekyb3d8bbwe");
                var best = candidates.OrderByDescending(c => LastUsed(c.Item2)).FirstOrDefault();
                if (best != null) { Process.Start(best.Item1); return true; }
                if (Directory.Exists(xboxLauncher)) { Process.Start("explorer.exe", "shell:AppsFolder\\Microsoft.4297127D64EC6_8wekyb3d8bbwe!Minecraft"); return true; }
            }
            catch (Exception e) { Util.Log("Could not open Minecraft: " + e.Message); }
            return false;
        }

        static DateTime LastUsed(string dir)
        {
            try { return Directory.Exists(dir) ? Directory.GetLastWriteTimeUtc(dir) : DateTime.MinValue; } catch { return DateTime.MinValue; }
        }
    }

    // ----------------------------------------------------------------------
    // Installer window: one obvious button per screen
    // ----------------------------------------------------------------------
    class SetupForm : Form
    {
        readonly string sourceCmd;
        readonly Panel body = new Panel();
        SetupOptions lastOptions;
        bool busy;

        public SetupForm(string sourceCmd)
        {
            this.sourceCmd = sourceCmd;
            Text = Config.AppName + " Setup";
            Icon = Util.AppIcon();
            Font = new Font("Segoe UI", 10f);
            BackColor = Ui.Bg;
            ForeColor = Ui.Ink;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(Ui.Scale(this, 580), Ui.Scale(this, 600));
            body.Dock = DockStyle.Fill;
            body.BackColor = Ui.Bg;
            Controls.Add(body);
            Controls.Add(Ui.Footer(this));
            Controls.Add(Ui.Header(this, "A hidden Minecraft server. One click to join.", 110));
            FormClosing += (s, e) => { if (busy) e.Cancel = true; };
            // (STUPRATOR_SIMULATE, the test switch, also shows the first-install screens.)
            if (Setup.IsInstalled() && Environment.GetEnvironmentVariable("STUPRATOR_SIMULATE") == null) ShowMaintenance(); else ShowWelcome();
        }

        protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); Ui.DarkTitleBar(this); }

        void ShowPage(Control page)
        {
            body.Controls.Clear();
            page.Dock = DockStyle.Fill;
            body.Controls.Add(page);
        }

        string CodeFile { get { return File.Exists(sourceCmd ?? "") ? sourceCmd : (File.Exists(Config.SourceCopy) ? Config.SourceCopy : null); } }

        FlowLayoutPanel SmallLinks(bool withOptions)
        {
            var links = Ui.Row();
            links.Margin = new Padding(0, 6, 0, 0);
            if (withOptions) links.Controls.Add(Ui.Link("Options", delegate { ShowOptions(false); }));
            if (CodeFile != null) links.Controls.Add(Ui.Link("Read the code", delegate { Util.OpenInNotepad(CodeFile); }));
            links.Controls.Add(Ui.Link("Cancel", delegate { Close(); }));
            return links;
        }

        // First screen. Detects the edition and offers one big button; only asks when it has to.
        void ShowWelcome()
        {
            bool java = Editions.JavaFound(), bedrock = Editions.BedrockFound();
            var p = Ui.Stack();
            if (java ^ bedrock)
            {
                p.Controls.Add(Ui.Text("Ready to install", 18f, FontStyle.Bold));
                var found = Ui.Text("We found Minecraft " + (java ? "Java Edition" : "Bedrock Edition") + " on this PC. " +
                    "Click the button and you're done. It takes about a minute.", 11f, FontStyle.Regular, Ui.Muted);
                p.Controls.Add(found);
                Ui.Wrap(this, found);
                var o = Setup.CurrentOptions();
                o.Java = java; o.Bedrock = bedrock;
                p.Controls.Add(Ui.Wide(this, "Install and play", delegate { Continue(o); }));
                p.Controls.Add(Ui.Link(java ? "I play Bedrock instead (or both)" : "I play Java instead (or both)", delegate { ShowChoice(false); }));
            }
            else
            {
                ShowChoice(!java && !bedrock);
                return;
            }
            p.Controls.Add(Note());
            p.Controls.Add(SmallLinks(true));
            ShowPage(p);
        }

        Label Note()
        {
            var note = Ui.Text(Ui.Bullet + " Downloads Tor (24 MB) from torproject.org and checks it's genuine\n" +
                Ui.Bullet + " No admin rights. Starts with Windows and waits quietly in the tray\n" +
                Ui.Bullet + " Remove it any time: Settings " + Ui.Arrow + " Apps " + Ui.Arrow + " Stuprator's Server", 9.5f, FontStyle.Regular, Ui.Muted);
            note.Margin = new Padding(0, 22, 0, 4);
            Ui.Wrap(this, note);
            return note;
        }

        void ShowChoice(bool nothingFound)
        {
            var p = Ui.Stack();
            p.Controls.Add(Ui.Text("Which Minecraft do you play?", 18f, FontStyle.Bold));
            var sub = Ui.Text(nothingFound
                ? "We couldn't find Minecraft on this PC. That's fine: pick the one you'll use."
                : "Pick one. You can change it later.", 11f, FontStyle.Regular, Ui.Muted);
            p.Controls.Add(sub);
            Ui.Wrap(this, sub);
            var o = Setup.CurrentOptions();
            p.Controls.Add(Ui.Tile(this, "Java Edition", "Minecraft Launcher, Prism, PolyMC, TLauncher...", delegate { o.Java = true; o.Bedrock = false; Continue(o); }));
            p.Controls.Add(Ui.Tile(this, "Bedrock Edition", "The Windows version from the Microsoft Store / Xbox app", delegate { o.Java = false; o.Bedrock = true; Continue(o); }));
            p.Controls.Add(Ui.Tile(this, "Both", "Set up both editions", delegate { o.Java = true; o.Bedrock = true; Continue(o); }));
            p.Controls.Add(SmallLinks(true));
            ShowPage(p);
        }

        void Continue(SetupOptions o)
        {
            if (o.Bedrock && !(Setup.IsInstalled() && Util.GetSetting("Bedrock", false))) ShowBedrockInfo(o);
            else RunInstall(o, false);
        }

        void ShowMaintenance()
        {
            var p = Ui.Stack();
            p.Controls.Add(Ui.Text("Already installed", 18f, FontStyle.Bold));
            p.Controls.Add(Ui.Text("What would you like to do?", 11f, FontStyle.Regular, Ui.Muted));
            p.Controls.Add(Ui.Tile(this, "Fix it", "Something's broken? This re-checks everything and repairs it", delegate { RunInstall(Setup.CurrentOptions(), true); }));
            p.Controls.Add(Ui.Tile(this, "Change settings", "Java or Bedrock, autostart, desktop shortcut", delegate { ShowOptions(true); }));
            p.Controls.Add(Ui.Tile(this, "Uninstall", "Remove Stuprator's Server from this PC", delegate { RunUninstall(); }));
            var links = Ui.Row();
            links.Controls.Add(Ui.Link("Close", delegate { Close(); }));
            p.Controls.Add(links);
            ShowPage(p);
        }

        void ShowOptions(bool changing)
        {
            var o = Setup.CurrentOptions();
            var p = Ui.Stack();
            p.Controls.Add(Ui.Text(changing ? "Settings" : "Options", 18f, FontStyle.Bold));
            p.Controls.Add(Ui.Text("Which Minecraft", 11f, FontStyle.Bold, Ui.Muted));
            var java = Ui.CheckBox("Java Edition", o.Java);
            var bedrock = Ui.CheckBox("Bedrock Edition (Windows)", o.Bedrock);
            p.Controls.Add(java);
            p.Controls.Add(bedrock);
            p.Controls.Add(Ui.Text("Extras", 11f, FontStyle.Bold, Ui.Muted));
            var auto = Ui.CheckBox("Start with Windows (waits quietly in the tray)", o.Autostart);
            var lists = Ui.CheckBox("Add the server to my Minecraft server list", o.ServerLists);
            var desk = Ui.CheckBox("Shortcut on my desktop", o.Desktop);
            p.Controls.Add(auto);
            p.Controls.Add(lists);
            p.Controls.Add(desk);
            var row = Ui.Row();
            row.Margin = new Padding(0, 16, 0, 0);
            row.Controls.Add(Ui.Button(changing ? "Save" : "Install and play", delegate
            {
                if (!java.Checked && !bedrock.Checked)
                {
                    MessageBox.Show(this, "Tick Java Edition, Bedrock Edition, or both.", Config.AppName, MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
                Continue(new SetupOptions { Autostart = auto.Checked, ServerLists = lists.Checked, Desktop = desk.Checked, Java = java.Checked, Bedrock = bedrock.Checked });
            }, true));
            row.Controls.Add(Ui.Button("Back", delegate { if (changing) ShowMaintenance(); else ShowWelcome(); }));
            p.Controls.Add(row);
            ShowPage(p);
        }

        // Shown when Bedrock is chosen: what works, what the server sees, and the one admin step
        // that the old Microsoft Store version needs.
        void ShowBedrockInfo(SetupOptions o)
        {
            bool needsAdmin = Editions.LoopbackExemptionNeeded();
            var p = Ui.Stack();
            p.Controls.Add(Ui.Text("Good to know about Bedrock", 18f, FontStyle.Bold));
            var card = Ui.CardPanel(this);
            var facts = Ui.Text(
                Ui.Bullet + " Windows PCs only. Phones, tablets and consoles can't join.\n" +
                Ui.Bullet + " Be signed in to your free Microsoft / Xbox account in Minecraft.\n" +
                Ui.Bullet + " The server sees your gamertag, never your IP address.\n" +
                Ui.Bullet + " If Minecraft asks whether to trust the server, say yes.", 10.5f);
            Ui.Wrap(this, facts);
            card.Controls.Add(facts);
            p.Controls.Add(card);
            CheckBox allow = null;
            if (needsAdmin)
            {
                var admin = Ui.Text(
                    "One extra step for your version. You have the older Microsoft Store Minecraft, which Windows " +
                    "won't let connect to programs on your own PC. Windows will ask \"Do you want to allow this app to " +
                    "make changes?\" for CheckNetIsolation, a tool built into Windows. Click Yes. It only lets Minecraft " +
                    "reach programs on this PC, and uninstalling undoes it.", 10f, FontStyle.Regular, Ui.Amber);
                Ui.Wrap(this, admin);
                p.Controls.Add(admin);
                allow = Ui.CheckBox("Allow it (Windows will ask for admin permission)", true);
                p.Controls.Add(allow);
            }
            p.Controls.Add(Ui.Wide(this, "Install and play", delegate
            {
                o.GrantLoopback = allow != null && allow.Checked;
                RunInstall(o, false);
            }));
            var links = Ui.Row();
            links.Controls.Add(Ui.Link("Back", delegate { if (Setup.IsInstalled()) ShowMaintenance(); else ShowWelcome(); }));
            if (CodeFile != null) links.Controls.Add(Ui.Link("Read the code (everything this program does is in it)", delegate { Util.OpenInNotepad(CodeFile); }));
            p.Controls.Add(links);
            ShowPage(p);
        }

        void RunInstall(SetupOptions o, bool repair)
        {
            lastOptions = o;
            var p = Ui.Stack();
            p.Controls.Add(Ui.Text(repair ? "Fixing things up..." : "Setting things up...", 18f, FontStyle.Bold));
            var step = Ui.Text("Starting...", 11.5f, FontStyle.Regular, Ui.Ink);
            Ui.Wrap(this, step);
            var bar = Ui.Bar(this);
            bar.Width = Ui.Scale(this, 520);
            bar.Height = Ui.Scale(this, 12);
            var hint = Ui.Text("This takes about a minute. You don't need to do anything.", 10f, FontStyle.Regular, Ui.Muted);
            var log = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, BackColor = Ui.Card, ForeColor = Ui.Muted,
                BorderStyle = BorderStyle.None, Width = Ui.Scale(this, 520), Height = Ui.Scale(this, 170), Font = new Font("Consolas", 9f), Visible = false };
            p.Controls.Add(step);
            p.Controls.Add(bar);
            p.Controls.Add(hint);
            p.Controls.Add(Ui.Link("Show details", delegate { log.Visible = !log.Visible; }));
            p.Controls.Add(log);
            ShowPage(p);
            busy = true;
            Action<string> say = s => BeginInvoke(new Action(() =>
            {
                log.AppendText(s + "\r\n");
                Util.Log("setup: " + s);
                step.Text = Friendly(s) ?? step.Text;
            }));
            Action<int> progress = v => BeginInvoke(new Action(() => bar.Value = Math.Max(0, Math.Min(100, v))));
            Task.Run(() =>
            {
                try
                {
                    var added = Setup.Install(o, sourceCmd, repair, say, progress);
                    BeginInvoke(new Action(() => { busy = false; ShowDone(o, added, repair); }));
                }
                catch (Exception e)
                {
                    Util.Log("Setup failed: " + e);
                    BeginInvoke(new Action(() => { busy = false; ShowError(e.Message, log.Text); }));
                }
            });
        }

        // Turns technical progress messages into plain words.
        static string Friendly(string s)
        {
            if (s.StartsWith("Downloading Tor")) return "Downloading Tor (the private network the server lives on)...";
            if (s.StartsWith("Checking the download")) return "Making sure the download is the real, untouched Tor...";
            if (s.StartsWith("Fingerprint matches") || s.StartsWith("Tor installed") || s.StartsWith("Tor is already")) return Ui.Check + " Tor is genuine. Setting up...";
            if (s.StartsWith("Adding the server")) return "Adding the server to your Minecraft...";
            if (s.StartsWith("Asking Windows")) return "Windows will ask for permission now. Click Yes.";
            if (s.StartsWith("Removing the older")) return "Removing the old version...";
            if (s.StartsWith("Closing the running")) return "Closing the running app...";
            return null;
        }

        void ShowDone(SetupOptions o, List<string> added, bool repair)
        {
            // Start the app right away (quietly if it was already running, the installer closed it).
            try { Process.Start(Config.ExePath); } catch { }
            var p = Ui.Stack();
            p.Controls.Add(Ui.Text(Ui.Check + "  You're all set!", 22f, FontStyle.Bold, Ui.Green));
            var how = Ui.Text(
                (o.Java ? "Java: Multiplayer " + Ui.Arrow + " \"Stuprator's Server\" " + Ui.Arrow + " Join Server\n" : "") +
                (o.Bedrock ? "Bedrock: Play " + Ui.Arrow + " Servers " + Ui.Arrow + " \"Stuprator's Server\"\n" : "") +
                "\nFirst time on the server, type in chat:   /register yourpassword yourpassword\n" +
                "Next times:   /login yourpassword", 11f);
            Ui.Wrap(this, how);
            var card = Ui.CardPanel(this);
            card.Controls.Add(how);
            p.Controls.Add(card);
            p.Controls.Add(Ui.Wide(this, "Open Minecraft", delegate
            {
                if (!Launchers.Open(o.Bedrock && !o.Java))
                    MessageBox.Show(this, "Open your Minecraft launcher, then pick \"Stuprator's Server\".", Config.AppName);
                Close();
            }));
            var links = Ui.Row();
            links.Controls.Add(Ui.Link("Close", delegate { Close(); }));
            p.Controls.Add(links);
            var tray = Ui.Text("The app is running in the tray (bottom-right, near the clock). It starts with Windows, so next time just open Minecraft.", 9.5f, FontStyle.Regular, Ui.Muted);
            if (!o.Autostart) tray.Text = "Next time, open \"Stuprator's Server\" from the Start menu before playing.";
            Ui.Wrap(this, tray);
            p.Controls.Add(tray);
            ShowPage(p);
        }

        void ShowError(string message, string details)
        {
            var p = Ui.Stack();
            p.Controls.Add(Ui.Text("That didn't work", 18f, FontStyle.Bold, Ui.Red));
            var m = Ui.Text(message + "\n\nCheck your internet and try again. If it keeps failing, click \"Copy details\" and send it to the server admin.", 10.5f);
            Ui.Wrap(this, m);
            p.Controls.Add(m);
            p.Controls.Add(Ui.Wide(this, "Try again", delegate { RunInstall(lastOptions ?? Setup.CurrentOptions(), true); }));
            var links = Ui.Row();
            links.Controls.Add(Ui.Link("Copy details", delegate
            {
                try { Clipboard.SetText("Stuprator's Server " + Config.Version + " setup error\r\n" + message + "\r\n\r\n" + details); } catch { }
            }));
            links.Controls.Add(Ui.Link("Close", delegate { Close(); }));
            p.Controls.Add(links);
            ShowPage(p);
        }

        void RunUninstall()
        {
            var answer = MessageBox.Show(this,
                "Remove Stuprator's Server from this PC?\n\nYour Minecraft worlds, settings and accounts are not touched.",
                "Uninstall", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (answer != DialogResult.Yes) return;
            busy = true;
            Task.Run(() =>
            {
                string error = null;
                try { Setup.Uninstall(s => { }, true); } catch (Exception e) { error = e.Message; }
                BeginInvoke(new Action(() =>
                {
                    busy = false;
                    var p = Ui.Stack();
                    p.Controls.Add(Ui.Text(error == null ? Ui.Check + "  Removed" : "Mostly removed", 20f, FontStyle.Bold, error == null ? Ui.Green : Ui.Amber));
                    p.Controls.Add(Ui.Text(error == null ? "Stuprator's Server is gone from this PC. Thanks for playing." : error, 11f));
                    p.Controls.Add(Ui.Wide(this, "Close", delegate { Close(); }));
                    ShowPage(p);
                }));
            });
        }
    }

    // ----------------------------------------------------------------------
    // The app: Tor + local Minecraft address, a tray icon, and three simple pages
    // ----------------------------------------------------------------------
    class AppForm : Form
    {
        readonly bool startHidden;
        bool started, reallyQuit, trayHintShown;

        // Play page
        readonly Label status = Ui.Text("Starting...", 22f, FontStyle.Bold, Ui.Amber);
        readonly ProgressBar progress = new ProgressBar();
        readonly TextBox address = new TextBox();
        readonly Button copy;
        readonly Button openGame;
        readonly Label serverLine = Ui.Text("", 10.5f, FontStyle.Regular, Ui.Muted);
        readonly Label steps = Ui.Text("Connecting to the Tor network. Usually under a minute; the very first time it can take a few minutes.", 10.5f);

        // Help page
        readonly TextBox logBox = new TextBox();
        readonly CheckBox autostartBox;

        readonly Panel content = new Panel();
        readonly Dictionary<string, Control> pages = new Dictionary<string, Control>();
        readonly Dictionary<string, Button> navButtons = new Dictionary<string, Button>();

        readonly NotifyIcon tray = new NotifyIcon();
        readonly System.Windows.Forms.Timer refresh = new System.Windows.Forms.Timer();

        Process tor;
        TcpListener listener, bedrockListener;
        UdpTunnel bedrockUdp;
        int socksPort, localPort, torRestarts;
        IPAddress listenIp = Config.LocalIp;
        volatile bool torReady, stopping;
        string lastPing = "not checked yet";
        int lastPercent = -1;
        DateTime connectStarted;

        public AppForm(bool startHidden)
        {
            this.startHidden = startHidden;
            Text = Config.AppName;
            Icon = Util.AppIcon();
            Font = new Font("Segoe UI", 10f);
            BackColor = Ui.Bg;
            ForeColor = Ui.Ink;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(Ui.Scale(this, 580), Ui.Scale(this, 600));

            copy = Ui.Button("Copy", delegate { CopyAddress(); });
            openGame = Ui.Wide(this, "Open Minecraft", delegate { OpenGame(); });
            autostartBox = Ui.CheckBox("Start with Windows (waits quietly in the tray)", Util.AutostartEnabled());

            pages["Play"] = PlayPage();
            pages["Help"] = HelpPage();
            pages["About"] = AboutPage();
            content.Dock = DockStyle.Fill;
            content.BackColor = Ui.Bg;

            var nav = new FlowLayoutPanel { Dock = DockStyle.Top, Height = Ui.Scale(this, 44), BackColor = Color.FromArgb(10, 7, 8), Padding = new Padding(Ui.Scale(this, 16), Ui.Scale(this, 6), 0, 0) };
            foreach (string name in new[] { "Play", "Help", "About" })
            {
                string n = name;
                var b = Ui.Button(name, delegate { ShowPage(n); });
                b.BackColor = Color.FromArgb(10, 7, 8);
                b.FlatAppearance.MouseOverBackColor = Ui.Card;
                b.Font = new Font("Segoe UI Semibold", 10.5f);
                navButtons[name] = b;
                nav.Controls.Add(b);
            }
            Controls.Add(content);
            Controls.Add(nav);
            Controls.Add(Ui.Footer(this));
            Controls.Add(Ui.Header(this, "A hidden Minecraft server", 86));
            ShowPage("Play");

            SetupTray();
            refresh.Interval = 60000;
            // Re-check the server once a minute, but only while the window is open (no background pings from the tray).
            refresh.Tick += async delegate { if (torReady && Visible) await CheckServer(); };

            FormClosing += OnClosingWindow;
            StartSignalListeners();
        }

        void ShowPage(string name)
        {
            content.Controls.Clear();
            content.Controls.Add(pages[name]);
            foreach (var kv in navButtons)
            {
                kv.Value.ForeColor = kv.Key == name ? Color.White : Ui.Muted;
                kv.Value.BackColor = kv.Key == name ? Ui.Accent : Color.FromArgb(10, 7, 8);
                kv.Value.FlatAppearance.MouseOverBackColor = kv.Key == name ? Ui.AccentHover : Ui.Card;
            }
            if (name == "Help") RefreshLog();
        }

        void OpenGame()
        {
            bool bedrockOnly = Util.GetSetting("Bedrock", false) && !Util.GetSetting("Java", true);
            if (!Launchers.Open(bedrockOnly))
                MessageBox.Show(this, "Open your Minecraft launcher, then pick \"Stuprator's Server\".", Config.AppName);
        }

        // ---------- pages ----------
        Control PlayPage()
        {
            var p = Ui.Stack();
            var card = Ui.CardPanel(this);
            card.Controls.Add(status);
            progress.Width = Ui.Scale(this, 484);
            progress.Height = Ui.Scale(this, 8);
            progress.Margin = new Padding(0, 2, 0, 10);
            card.Controls.Add(progress);
            card.Controls.Add(serverLine);
            Ui.Wrap(this, serverLine);
            p.Controls.Add(card);

            openGame.Enabled = false;
            p.Controls.Add(openGame);

            steps.Margin = new Padding(0, 6, 0, 14);
            Ui.Wrap(this, steps);
            p.Controls.Add(steps);

            var row = Ui.Row();
            row.WrapContents = false;
            var lbl = Ui.Text("Server address", 9.5f, FontStyle.Regular, Ui.Muted);
            lbl.Margin = new Padding(0, 9, 10, 0);
            address.ReadOnly = true;
            address.Text = "please wait...";
            address.Font = new Font("Consolas", 13f, FontStyle.Bold);
            address.BackColor = Ui.Card;
            address.ForeColor = Ui.Ink;
            address.BorderStyle = BorderStyle.None;
            address.TextAlign = HorizontalAlignment.Center;
            address.Width = Ui.Scale(this, 230);
            address.Margin = new Padding(0, 8, 10, 0);
            address.Enabled = false;
            copy.Enabled = false;
            row.Controls.Add(lbl);
            row.Controls.Add(address);
            row.Controls.Add(copy);
            p.Controls.Add(row);
            return p;
        }

        Control AboutPage()
        {
            var p = Ui.Stack();
            var title = Ui.Text("What this program does", 16f, FontStyle.Bold);
            var body = Ui.Text(
                "It connects your Minecraft to Stuprator's Server. The server lives on the Tor network, so nobody can find " +
                "where it runs, and it never sees your real IP address.\n\n" +
                "Minecraft can't use Tor by itself, so this program:\n" +
                "  1. Runs Tor (the official program from the Tor Project) in the background.\n" +
                "  2. Opens a private address on your own PC, " + Config.LocalAddress + ", that only your PC can use.\n" +
                "  3. Sends Minecraft's connection from that address through Tor to the server. For Bedrock it also " +
                "packs Bedrock's UDP traffic into a Tor connection, because Tor only carries TCP.\n\n" +
                "It does not look at your personal files or send anything anywhere except to the server through Tor. " +
                "The only Minecraft files it opens are the server lists, to add one entry. Admin rights are only ever " +
                "asked for once, for the old Microsoft Store Bedrock, and only if you agree.", 10f);
            var facts = Ui.Text(
                "Connects you to: " + Config.ServerOnion + ":" + Config.ServerPort + "\n" +
                "Version " + Config.Version + "  " + Ui.Bullet + "  Tor " + Config.TorVersion + "\n" +
                "Program: " + Config.InstallDir + "\n" +
                "Data and logs: " + Config.DataDir, 9f, FontStyle.Regular, Ui.Muted);
            var credit = Ui.Text(Config.Credit, 11f, FontStyle.Bold | FontStyle.Italic, Ui.AccentHover);
            var row = Ui.Row();
            row.Controls.Add(Ui.Button("Read the source code", delegate
            {
                if (File.Exists(Config.SourceCopy)) Util.OpenInNotepad(Config.SourceCopy);
                else MessageBox.Show(this, "The source file was not kept on this PC. It is the installer file you downloaded.", Config.AppName);
            }));
            row.Controls.Add(Ui.Button("Open program folder", delegate { Util.OpenFolder(Config.InstallDir); }));
            p.Controls.Add(title);
            p.Controls.Add(body);
            p.Controls.Add(row);
            p.Controls.Add(facts);
            p.Controls.Add(credit);
            Ui.Wrap(this, body, facts);
            return p;
        }

        Control HelpPage()
        {
            var p = Ui.Stack();
            p.Controls.Add(Ui.Text("Something wrong?", 16f, FontStyle.Bold));
            var tips = Ui.Text(
                "1. Click Reconnect.   2. Still stuck? Click \"Copy problem report\" and send it to the server admin.\n" +
                "Minecraft says \"Outdated\" or \"blocked\"? Java players: use " + Config.JavaVersions.Replace("Java Edition ", "") + ".", 10f, FontStyle.Regular, Ui.Muted);
            Ui.Wrap(this, tips);
            p.Controls.Add(tips);
            var row1 = Ui.Row();
            row1.Controls.Add(Ui.Button("Reconnect", delegate { Reconnect(); }, true));
            row1.Controls.Add(Ui.Button("Copy problem report", delegate { CopyReport(); }));
            p.Controls.Add(row1);
            var row2 = Ui.Row();
            row2.Controls.Add(Ui.Button("Fix / change settings", delegate { RunSetup("--setup"); }));
            row2.Controls.Add(Ui.Button("Open log folder", delegate { Util.OpenFolder(Config.LogDir); }));
            row2.Controls.Add(Ui.Button("Uninstall", delegate { RunSetup("--uninstall"); }));
            if (Util.GetSetting("Bedrock", false) && Editions.LoopbackExemptionNeeded())
                row2.Controls.Add(Ui.Button("Allow Bedrock (admin)", delegate
                {
                    var ok = MessageBox.Show(this,
                        "Windows will ask for admin permission to let your Microsoft Store Minecraft connect to programs on this PC.\n\n" +
                        "It runs: CheckNetIsolation LoopbackExempt -a -n=" + Config.BedrockUwpFamily,
                        Config.AppName, MessageBoxButtons.OKCancel, MessageBoxIcon.Information);
                    if (ok != DialogResult.OK) return;
                    if (Editions.SetLoopbackExemption(true))
                    {
                        Util.SetSetting("AddedLoopback", true);
                        MessageBox.Show(this, "Done. Restart Minecraft, then join.", Config.AppName);
                    }
                    else MessageBox.Show(this, "Not changed (the admin prompt was declined or failed).", Config.AppName);
                }));
            p.Controls.Add(row2);
            autostartBox.CheckedChanged += delegate
            {
                try { Util.SetAutostart(autostartBox.Checked); Util.Log("Autostart set to " + autostartBox.Checked); }
                catch (Exception e) { MessageBox.Show(this, "Could not change autostart: " + e.Message, Config.AppName); }
            };
            p.Controls.Add(autostartBox);
            logBox.Multiline = true;
            logBox.ReadOnly = true;
            logBox.ScrollBars = ScrollBars.Vertical;
            logBox.WordWrap = false;
            logBox.Font = new Font("Consolas", 8.5f);
            logBox.BackColor = Ui.Card;
            logBox.ForeColor = Ui.Muted;
            logBox.BorderStyle = BorderStyle.None;
            logBox.Width = Ui.Scale(this, 520);
            logBox.Height = Ui.Scale(this, 150);
            p.Controls.Add(logBox);
            return p;
        }

        void RefreshLog()
        {
            logBox.Text = string.Join("\r\n", Util.LogTail(150));
            logBox.SelectionStart = logBox.Text.Length;
            logBox.ScrollToCaret();
        }

        // ---------- window / tray behaviour ----------
        protected override void SetVisibleCore(bool value)
        {
            if (startHidden && !IsHandleCreated)
            {
                CreateHandle();
                value = false;
            }
            base.SetVisibleCore(value);
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            Ui.DarkTitleBar(this);
            if (!started)
            {
                started = true;
                BeginInvoke(new Action(Start));
            }
        }

        void SetupTray()
        {
            tray.Icon = Util.AppIcon();
            tray.Text = Config.AppName;
            var menu = new ContextMenuStrip();
            menu.Items.Add("Open Minecraft", null, delegate { OpenGame(); });
            menu.Items.Add("Show Stuprator's Server", null, delegate { ShowWindow(); });
            menu.Items.Add("Reconnect", null, delegate { Reconnect(); });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Quit", null, delegate { Quit(); });
            tray.ContextMenuStrip = menu;
            tray.DoubleClick += delegate { ShowWindow(); };
            tray.Visible = true;
        }

        void ShowWindow()
        {
            Show();
            WindowState = FormWindowState.Normal;
            Activate();
            BringToFront();
        }

        void Quit()
        {
            reallyQuit = true;
            Close();
        }

        void OnClosingWindow(object sender, FormClosingEventArgs e)
        {
            if (!reallyQuit && e.CloseReason == CloseReason.UserClosing && Util.AutostartEnabled())
            {
                Util.Log("Window closed; still running in the tray");
                e.Cancel = true;
                Hide();
                if (!trayHintShown)
                {
                    trayHintShown = true;
                    tray.ShowBalloonTip(5000, Config.AppName, "Still running in the tray, so you can join any time. Right-click the icon to quit.", ToolTipIcon.Info);
                }
                return;
            }
            Util.Log("Quitting (" + (reallyQuit ? "Quit chosen" : e.CloseReason.ToString()) + ")");
            StopConnection();
            tray.Visible = false;
            tray.Dispose();
        }

        void StartSignalListeners()
        {
            var show = new EventWaitHandle(false, EventResetMode.AutoReset, Config.ShowEventName);
            var quit = new EventWaitHandle(false, EventResetMode.AutoReset, Config.QuitEventName);
            var t = new Thread(() =>
            {
                while (true)
                {
                    int which = WaitHandle.WaitAny(new WaitHandle[] { show, quit });
                    try { BeginInvoke(new Action(() => { if (which == 0) ShowWindow(); else Quit(); })); } catch { return; }
                }
            });
            t.IsBackground = true;
            t.Start();
        }

        void RunSetup(string arg)
        {
            try { Process.Start(Config.ExePath, arg); } catch (Exception e) { MessageBox.Show(this, e.Message, Config.AppName); }
        }

        // ---------- status helpers ----------
        void UI(Action a)
        {
            if (IsDisposed) return;
            try { if (InvokeRequired) BeginInvoke(a); else a(); } catch (InvalidOperationException) { }
        }

        void SetStatus(string text, Color color, string trayText)
        {
            UI(() =>
            {
                status.Text = text;
                status.ForeColor = color;
                openGame.Enabled = torReady;
                string t = Config.AppName + " - " + trayText;
                tray.Text = t.Length > 63 ? t.Substring(0, 63) : t;
            });
        }

        void Fail(string headline, string help)
        {
            Util.Log("Problem: " + headline + " - " + help);
            SetStatus(headline, Ui.Red, "problem, click to open");
            UI(() => { progress.Style = ProgressBarStyle.Continuous; steps.Text = help; });
        }

        void CopyAddress()
        {
            if (!torReady) { ShowWindow(); return; }
            try { Clipboard.SetText(address.Text); copy.Text = "Copied!"; } catch { }
        }

        void CopyReport()
        {
            var sb = new StringBuilder();
            sb.AppendLine("Stuprator's Server problem report");
            sb.AppendLine("Version " + Config.Version + ", Tor " + Config.TorVersion + ", Windows " + Environment.OSVersion.Version + (Environment.Is64BitOperatingSystem ? " 64-bit" : " 32-bit"));
            sb.AppendLine("Status: " + status.Text);
            sb.AppendLine("Tor ready: " + torReady + ", bootstrap " + lastPercent + "%, restarts " + torRestarts);
            sb.AppendLine("Tor files verified: " + Util.TorFilesOk());
            sb.AppendLine("Local address: " + listenIp + ":" + localPort + ", Tor SOCKS port " + socksPort);
            sb.AppendLine("Editions: Java=" + Util.GetSetting("Java", true) + " Bedrock=" + Util.GetSetting("Bedrock", false));
            sb.AppendLine("Last server check: " + lastPing);
            sb.AppendLine("Autostart: " + Util.AutostartEnabled());
            sb.AppendLine("Launchers found: " + string.Join("; ", ServerLists.FindGameFolders().Select(k => k.Key)));
            sb.AppendLine("--- last log lines ---");
            foreach (var line in Util.LogTail(60)) sb.AppendLine(line);
            try { Clipboard.SetText(sb.ToString()); MessageBox.Show(this, "Problem report copied. Paste it in a message to the server admin.", Config.AppName); } catch { }
        }

        // ---------- connection ----------
        void Start()
        {
            stopping = false;
            torReady = false;
            lastPercent = -1;
            connectStarted = DateTime.Now;
            UI(() =>
            {
                progress.Style = ProgressBarStyle.Continuous;
                progress.Value = 0;
                address.Enabled = false;
                copy.Enabled = false;
                address.Text = "please wait...";
                serverLine.Text = "";
                steps.Text = "Connecting to the Tor network. Usually under a minute; the very first time it can take a few minutes.";
            });

            if (!Util.TorFilesOk())
            {
                Fail("Tor files are damaged or missing", "Open the \"Help & fixes\" tab and click \"Repair / change settings\", then Repair.");
                return;
            }

            listenIp = Config.LocalIp;
            localPort = 0;
            socksPort = FirstFreePort(IPAddress.Loopback, 19150);
            if (socksPort == 0)
            {
                Fail("No free port", "Close other Minecraft servers or proxy programs on this PC, then click Reconnect.");
                return;
            }

            string torData = Path.Combine(Config.DataDir, "tor-data");
            Directory.CreateDirectory(torData);
            string torrc = Path.Combine(torData, "torrc");
            File.WriteAllText(torrc, "# Settings are passed on the command line by Stuprator's Server.\n");

            var info = new ProcessStartInfo(Config.TorExe);
            info.Arguments = string.Join(" ", new[] {
                "-f", Q(torrc),
                "--SocksPort", Q("127.0.0.1:" + socksPort),
                "--DataDirectory", Q(torData),
                "--GeoIPFile", Q(Config.GeoipFile),
                "--GeoIPv6File", Q(Config.Geoip6File),
                "--ClientOnly", "1",
                "--Log", Q("notice stdout"),
                "--__OwningControllerProcess", Process.GetCurrentProcess().Id.ToString()
            });
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            info.WorkingDirectory = Path.GetDirectoryName(Config.TorExe);

            try
            {
                var proc = new Process();
                proc.StartInfo = info;
                proc.EnableRaisingEvents = true;
                proc.OutputDataReceived += OnTorLine;
                proc.ErrorDataReceived += OnTorLine;
                proc.Exited += delegate { OnTorExited(proc); };
                proc.Start();
                proc.BeginOutputReadLine();
                proc.BeginErrorReadLine();
                tor = proc;
                Util.Log("Tor started (SOCKS 127.0.0.1:" + socksPort + ")");
            }
            catch (Exception e)
            {
                Fail("Could not start Tor", "Windows or your antivirus blocked tor.exe (" + e.Message + "). Allow it, then click Reconnect.");
                return;
            }
            SetStatus("Connecting to Tor... 0%", Ui.Amber, "connecting");

            var slow = new System.Windows.Forms.Timer { Interval = 120000 };
            slow.Tick += delegate
            {
                slow.Stop();
                slow.Dispose();
                if (!torReady && !stopping)
                    UI(() => steps.Text = "This is taking long. Some school, work or public Wi-Fi networks block Tor. Try home internet or a phone hotspot, or keep waiting.");
            };
            slow.Start();
        }

        static string Q(string s) { return "\"" + s.Replace("\"", "") + "\""; }

        void OnTorExited(Process proc)
        {
            if (stopping || proc != tor) return;
            torReady = false;
            Util.Log("Tor exited unexpectedly (code " + SafeExitCode(proc) + ")");
            if (torRestarts < 3)
            {
                torRestarts++;
                UI(() => { StopListener(); Start(); });
            }
            else Fail("Tor keeps stopping", "Click Reconnect. If it happens again, copy the problem report on the Help tab and send it to the admin.");
        }

        static string SafeExitCode(Process p) { try { return p.ExitCode.ToString(); } catch { return "?"; } }

        void OnTorLine(object sender, DataReceivedEventArgs e)
        {
            if (e.Data == null) return;
            string line = e.Data;
            int idx = line.IndexOf("[", StringComparison.Ordinal);
            Util.Log("tor: " + (idx >= 0 ? line.Substring(idx) : line));
            if (torReady) return;
            Match m = Regex.Match(line, @"Bootstrapped (\d+)%");
            if (!m.Success) return;
            int pct = int.Parse(m.Groups[1].Value);
            if (pct == lastPercent) return;
            lastPercent = pct;
            UI(() => progress.Value = Math.Min(100, pct));
            SetStatus("Connecting to Tor... " + pct + "%", Ui.Amber, "connecting " + pct + "%");
            if (pct >= 100)
            {
                torReady = true;
                UI(() => { var ignored = AfterTorReady(); });
            }
        }

        async Task AfterTorReady()
        {
            if (stopping) return;
            listener = TryListenForJava(Config.LocalIp, Config.PreferredLocalPort)
                ?? TryListenForJava(IPAddress.Loopback, Config.PreferredLocalPort);
            if (listener == null)
            {
                torReady = false;
                Fail("No free port", "Close other Minecraft servers or proxy programs on this PC, then click Reconnect.");
                return;
            }
            var endpoint = (IPEndPoint)listener.LocalEndpoint;
            listenIp = endpoint.Address;
            localPort = endpoint.Port;
            var acceptLoop = AcceptLoop(listener, Config.ServerPort);
            bool bedrockOn = Util.GetSetting("Bedrock", false);
            bool javaOn = Util.GetSetting("Java", true) || !bedrockOn;
            string bedrockNote = bedrockOn ? StartBedrock() : null;
            Util.Log("Tor ready after " + (int)(DateTime.Now - connectStarted).TotalSeconds + "s; Minecraft listening on " + endpoint);

            string addr = listenIp + (localPort == 25565 ? "" : ":" + localPort);
            // Keep the player's existing server-list entries pointing at the address in use today.
            if (Util.GetSetting("AddToServerLists", false) && Util.GetSetting("Java", true))
                { var ignoredUpdate = Task.Run(() => ServerLists.UpdateExisting(addr)); }
            address.Text = addr;
            address.Enabled = true;
            copy.Enabled = true;
            copy.Text = "Copy";
            progress.Style = ProgressBarStyle.Marquee;
            SetStatus("Checking the server...", Ui.Amber, "checking server");
            steps.Text = "Tor is connected. Reaching the server (this can take 10-30 seconds).";

            bool up = false;
            for (int attempt = 1; attempt <= 4 && !up && !stopping; attempt++)
            {
                up = await CheckServer();
                if (!up && attempt < 4) await Task.Delay(3000);
            }
            progress.Style = ProgressBarStyle.Continuous;
            progress.Value = 100;
            refresh.Start();

            bool listed = Util.GetSetting("AddToServerLists", false);
            var text = new StringBuilder();
            if (javaOn)
            {
                text.Append(bedrockOn ? "JAVA EDITION (" + Config.JavaVersions.Replace("Java Edition ", "") + ")\n"
                                      : "Open Minecraft (" + Config.JavaVersions + "):\n");
                text.Append(listed && localPort == 25565
                    ? "     Multiplayer  >  \"Stuprator's Server\"  >  Join Server   (or Add Server: " + addr + ")\n"
                    : "     Multiplayer  >  Add Server  >  paste " + addr + "  >  Done  >  Join\n");
            }
            if (bedrockOn)
            {
                text.Append("BEDROCK EDITION (Windows)\n");
                text.Append(bedrockNote ?? ("     Play  >  Servers  >  \"Stuprator's Server\"   (or Add Server: " + Config.LocalAddress + ", port " + Config.BedrockLocalPort + ")\n"));
            }
            text.Append("\nFirst time: type  /register <password> <password>  in chat.\nAfter that:  /login <password>.  Use a password you use nowhere else.");
            if (localPort != 25565)
                text.Append("\n\nNote: something else on this PC uses the usual Java port, so use exactly " + addr + " today.");
            steps.Text = text.ToString();
            await acceptLoop;
        }

        // Bedrock: TCP 127.66.6.66:19160 carries NetherNet signaling, UDP 127.66.6.66:19160 carries
        // the game itself. Returns a message for the player if something is wrong, else null.
        string StartBedrock()
        {
            try
            {
                bedrockListener = new TcpListener(Config.LocalIp, Config.BedrockLocalPort);
                bedrockListener.Start();
                var ignored = AcceptLoop(bedrockListener, Config.BedrockSignalingPort);
                bedrockUdp = new UdpTunnel(this, Config.BedrockLocalPort);
                var ignored2 = bedrockUdp.Run();
                Util.Log("Bedrock tunnel listening on " + Config.LocalAddress + ":" + Config.BedrockLocalPort + " (TCP + UDP)");
            }
            catch (Exception e)
            {
                Util.Log("Bedrock tunnel could not start: " + e.Message);
                return "     Not available right now: port " + Config.BedrockLocalPort + " is taken by another program. Close it and click Reconnect.\n";
            }
            if (Editions.LoopbackExemptionNeeded())
                return "     Your Microsoft Store Minecraft still needs permission to connect to this PC.\n" +
                       "     Open the \"Help & fixes\" tab and click \"Allow Bedrock (admin)\".\n";
            return null;
        }

        async Task<bool> CheckServer()
        {
            try
            {
                var info = await PingServer();
                lastPing = DateTime.Now.ToString("HH:mm:ss") + " online, " + info.Item2 + "/" + info.Item3 + ", " + info.Item1;
                SetStatus("Ready - join now", Ui.Green, "ready, " + info.Item2 + "/" + info.Item3 + " players");
                UI(() =>
                {
                    serverLine.Text = "Server online  |  " + info.Item2 + " of " + info.Item3 + " players  |  " + info.Item1;
                    serverLine.ForeColor = Ui.Green;
                });
                return true;
            }
            catch (Exception e)
            {
                lastPing = DateTime.Now.ToString("HH:mm:ss") + " no answer (" + e.Message + ")";
                Util.Log("Server check: " + lastPing);
                SetStatus("Server not answering", Ui.Amber, "server not answering");
                UI(() =>
                {
                    serverLine.Text = "Tor works, but the server did not reply. It may be off or restarting. You can still try to join.";
                    serverLine.ForeColor = Ui.Amber;
                });
                return false;
            }
        }

        void Reconnect()
        {
            Util.Log("Reconnect requested");
            torRestarts = 0;
            StopConnection();
            Start();
        }

        void StopListener()
        {
            refresh.Stop();
            try { if (listener != null) listener.Stop(); } catch { }
            try { if (bedrockListener != null) bedrockListener.Stop(); } catch { }
            bedrockListener = null;
            if (bedrockUdp != null) bedrockUdp.Stop();
            bedrockUdp = null;
            listener = null;
        }

        void StopConnection()
        {
            stopping = true;
            torReady = false;
            StopListener();
            try { if (tor != null && !tor.HasExited) tor.Kill(); } catch { }
            tor = null;
        }

        static bool PortFree(IPAddress ip, int port)
        {
            try { var l = new TcpListener(ip, port); l.Start(); l.Stop(); return true; }
            catch (SocketException) { return false; }
        }

        static int FirstFreePort(IPAddress ip, int start)
        {
            for (int p = start; p < start + 50; p++) if (PortFree(ip, p)) return p;
            return 0;
        }

        static TcpListener TryListenForJava(IPAddress address, int preferredPort)
        {
            int end = preferredPort + Config.JavaPortSearchCount;
            for (int port = preferredPort; port < end; port++)
            {
                var candidate = new TcpListener(address, port);
                try
                {
                    candidate.ExclusiveAddressUse = true;
                    candidate.Start();
                    return candidate;
                }
                catch (SocketException) { candidate.Stop(); }
            }
            return null;
        }

        async Task AcceptLoop(TcpListener l, int onionPort)
        {
            while (true)
            {
                TcpClient player;
                try { player = await l.AcceptTcpClientAsync(); }
                catch (Exception) { return; }
                var ignored = Bridge(player, onionPort);
            }
        }

        async Task Bridge(TcpClient player, int onionPort)
        {
            TcpClient remote = null;
            try
            {
                player.NoDelay = true;
                remote = await OpenThroughTor(onionPort);
                remote.NoDelay = true;
                NetworkStream a = player.GetStream(), b = remote.GetStream();
                await Task.WhenAny(a.CopyToAsync(b), b.CopyToAsync(a));
            }
            catch (Exception e) { Util.Log("Player connection ended: " + e.Message); }
            finally
            {
                try { player.Close(); } catch { }
                if (remote != null) try { remote.Close(); } catch { }
            }
        }

        // SOCKS5 connect to the server's onion address through the local Tor.
        async Task<TcpClient> OpenThroughTor(int port = Config.ServerPort)
        {
            var client = new TcpClient();
            await client.ConnectAsync(IPAddress.Loopback, socksPort);
            NetworkStream s = client.GetStream();
            // 90 s: the first connection to an onion service after a fresh Tor start can be slow.
            using (var cts = new CancellationTokenSource(90000))
            using (cts.Token.Register(() => client.Close()))
            {
                try
                {
                    await s.WriteAsync(new byte[] { 5, 1, 0 }, 0, 3);
                    byte[] hello = await ReadExact(s, 2);
                    if (hello[0] != 5 || hello[1] != 0) throw new IOException("Tor refused the connection");
                    byte[] host = Encoding.ASCII.GetBytes(Config.ServerOnion);
                    var req = new List<byte> { 5, 1, 0, 3, (byte)host.Length };
                    req.AddRange(host);
                    req.Add((byte)(port >> 8));
                    req.Add((byte)(port & 255));
                    await s.WriteAsync(req.ToArray(), 0, req.Count);
                    byte[] head = await ReadExact(s, 4);
                    if (head[1] != 0) throw new IOException("server unreachable through Tor (code " + head[1] + ")");
                    int rest = head[3] == 1 ? 4 : head[3] == 4 ? 16 : (await ReadExact(s, 1))[0];
                    await ReadExact(s, rest + 2);
                }
                catch (Exception)
                {
                    client.Close();
                    if (cts.IsCancellationRequested) throw new IOException("timed out reaching the server");
                    throw;
                }
            }
            return client;
        }

        // Bedrock talks UDP, Tor carries TCP. Each Bedrock client (one local UDP address)
        // gets its own Tor stream to the server's relay, and every datagram travels as
        // [2-byte big-endian length][datagram]. The relay on the server does the reverse.
        class UdpTunnel
        {
            const int MaxSessions = 32, MaxDatagram = 4096, MaxQueued = 256;
            readonly AppForm app;
            readonly UdpClient udp;
            readonly Dictionary<string, Session> sessions = new Dictionary<string, Session>();
            readonly object gate = new object();

            class Session
            {
                public IPEndPoint Client;
                public TcpClient Tcp;
                public NetworkStream Stream;
                public Task<bool> Ready;
                public readonly SemaphoreSlim WriteLock = new SemaphoreSlim(1, 1);
                public int Queued;
                public bool Dead;
            }

            public UdpTunnel(AppForm app, int port)
            {
                this.app = app;
                udp = new UdpClient(new IPEndPoint(Config.LocalIp, port));
                // Windows reports "connection reset" on UDP after sending to a closed port; ignore that.
                const int SIO_UDP_CONNRESET = -1744830452;
                try { udp.Client.IOControl(SIO_UDP_CONNRESET, new byte[] { 0, 0, 0, 0 }, null); } catch { }
            }

            public async Task Run()
            {
                while (true)
                {
                    UdpReceiveResult r;
                    try { r = await udp.ReceiveAsync(); }
                    catch (ObjectDisposedException) { return; }
                    catch (SocketException) { continue; }
                    if (r.Buffer.Length == 0 || r.Buffer.Length > MaxDatagram) continue;
                    Session s = GetOrOpen(r.RemoteEndPoint);
                    if (s != null) { var ignored = Send(s, r.Buffer); }
                }
            }

            Session GetOrOpen(IPEndPoint client)
            {
                lock (gate)
                {
                    Session s;
                    string key = client.ToString();
                    if (sessions.TryGetValue(key, out s) && !s.Dead) return s;
                    if (sessions.Count >= MaxSessions) return null;
                    s = new Session { Client = client };
                    sessions[key] = s;
                    s.Ready = Connect(s);
                    return s;
                }
            }

            async Task<bool> Connect(Session s)
            {
                try
                {
                    s.Tcp = await app.OpenThroughTor(Config.BedrockRelayPort);
                    s.Tcp.NoDelay = true;
                    s.Stream = s.Tcp.GetStream();
                    var ignored = Pump(s);
                    return true;
                }
                catch (Exception e)
                {
                    Util.Log("Bedrock tunnel could not reach the server: " + e.Message);
                    Close(s);
                    return false;
                }
            }

            async Task Send(Session s, byte[] data)
            {
                // If Tor falls far behind, drop the datagram; the game resends what matters.
                if (Interlocked.Increment(ref s.Queued) > MaxQueued) { Interlocked.Decrement(ref s.Queued); return; }
                try
                {
                    if (!await s.Ready) return;
                    byte[] frame = new byte[data.Length + 2];
                    frame[0] = (byte)(data.Length >> 8);
                    frame[1] = (byte)(data.Length & 255);
                    Buffer.BlockCopy(data, 0, frame, 2, data.Length);
                    await s.WriteLock.WaitAsync();
                    try { await s.Stream.WriteAsync(frame, 0, frame.Length); }
                    finally { s.WriteLock.Release(); }
                }
                catch (Exception) { Close(s); }
                finally { Interlocked.Decrement(ref s.Queued); }
            }

            // Server -> Bedrock: unwrap frames and send them as UDP to the game.
            async Task Pump(Session s)
            {
                try
                {
                    while (true)
                    {
                        byte[] head = await ReadExact(s.Stream, 2);
                        int n = (head[0] << 8) | head[1];
                        if (n == 0 || n > MaxDatagram) break;
                        byte[] data = await ReadExact(s.Stream, n);
                        await udp.SendAsync(data, data.Length, s.Client);
                    }
                }
                catch (Exception) { }
                finally { Close(s); }
            }

            void Close(Session s)
            {
                lock (gate)
                {
                    s.Dead = true;
                    Session current;
                    string key = s.Client.ToString();
                    if (sessions.TryGetValue(key, out current) && current == s) sessions.Remove(key);
                }
                try { if (s.Tcp != null) s.Tcp.Close(); } catch { }
            }

            public int ActiveSessions { get { lock (gate) return sessions.Count; } }

            public void Stop()
            {
                try { udp.Close(); } catch { }
                lock (gate)
                {
                    foreach (var s in sessions.Values.ToList()) try { if (s.Tcp != null) s.Tcp.Close(); } catch { }
                    sessions.Clear();
                }
            }
        }

        static async Task<byte[]> ReadExact(Stream s, int n)
        {
            byte[] buf = new byte[n];
            int got = 0;
            while (got < n)
            {
                int k = await s.ReadAsync(buf, got, n - got);
                if (k <= 0) throw new IOException("connection closed");
                got += k;
            }
            return buf;
        }

        // Minecraft "server list ping", the same request the game's server list makes.
        async Task<Tuple<string, int, int>> PingServer()
        {
            using (TcpClient c = await OpenThroughTor())
            using (var cts = new CancellationTokenSource(30000))
            using (cts.Token.Register(() => c.Close()))
            {
                NetworkStream s = c.GetStream();
                var hs = new List<byte>();
                VarInt(hs, 0);
                VarInt(hs, -1);
                byte[] h = Encoding.ASCII.GetBytes(Config.ServerOnion);
                VarInt(hs, h.Length);
                hs.AddRange(h);
                hs.Add((byte)(Config.ServerPort >> 8));
                hs.Add((byte)(Config.ServerPort & 255));
                VarInt(hs, 1);
                var packet = new List<byte>();
                VarInt(packet, hs.Count);
                packet.AddRange(hs);
                packet.Add(1);
                packet.Add(0);
                await s.WriteAsync(packet.ToArray(), 0, packet.Count);

                int length = await ReadVarInt(s);
                if (length <= 0 || length > 1 << 20) throw new IOException("bad reply");
                byte[] body = await ReadExact(s, length);
                int offset = 0;
                VarIntAt(body, ref offset);
                int jsonLen = VarIntAt(body, ref offset);
                string json = Encoding.UTF8.GetString(body, offset, Math.Min(jsonLen, body.Length - offset));
                Match ver = Regex.Match(json, "\"version\"\\s*:\\s*\\{[^}]*?\"name\"\\s*:\\s*\"([^\"]*)\"");
                Match players = Regex.Match(json, "\"players\"\\s*:\\s*\\{[^}]*\\}");
                string pj = players.Success ? players.Value : json;
                Match max = Regex.Match(pj, "\"max\"\\s*:\\s*(\\d+)");
                Match online = Regex.Match(pj, "\"online\"\\s*:\\s*(\\d+)");
                return Tuple.Create(ver.Success ? ver.Groups[1].Value : "unknown version",
                    online.Success ? int.Parse(online.Groups[1].Value) : 0,
                    max.Success ? int.Parse(max.Groups[1].Value) : 0);
            }
        }

        static void VarInt(List<byte> b, int value)
        {
            uint v = (uint)value;
            while (v >= 0x80) { b.Add((byte)(v | 0x80)); v >>= 7; }
            b.Add((byte)v);
        }

        static async Task<int> ReadVarInt(Stream s)
        {
            int value = 0;
            for (int i = 0; i < 5; i++)
            {
                byte b = (await ReadExact(s, 1))[0];
                value |= (b & 0x7F) << (7 * i);
                if ((b & 0x80) == 0) return value;
            }
            throw new IOException("bad number");
        }

        static int VarIntAt(byte[] buf, ref int offset)
        {
            int value = 0;
            for (int i = 0; i < 5 && offset < buf.Length; i++)
            {
                byte b = buf[offset++];
                value |= (b & 0x7F) << (7 * i);
                if ((b & 0x80) == 0) return value;
            }
            throw new IOException("bad number");
        }
    }
}
