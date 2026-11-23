# Builds the single-file installer: header.cmd + StupratorsServer.cs -> "Install-Stuprators-Server.cmd"
# Also compiles it once here so build errors show up before players see them.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$out = Join-Path $root "dist\Install-Stuprators-Server.cmd"
New-Item -ItemType Directory -Force -Path (Join-Path $root 'dist') | Out-Null

$header = Get-Content -Raw (Join-Path $root 'src\header.cmd')
$source = Get-Content -Raw (Join-Path $root 'src\StupratorsServer.cs')
$text = ($header.TrimEnd() + "`n" + $source) -replace "`r?`n", "`r`n"
if ($text -match '[^\x00-\x7F]') { throw 'Installer must be plain ASCII (the cmd "more" command mangles other characters).' }
[IO.File]::WriteAllText($out, $text, [Text.Encoding]::ASCII)

$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$check = Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $check | Out-Null
& $csc /nologo /target:winexe /optimize+ /out:"$check\Stuprators Server.exe" /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:Microsoft.CSharp.dll (Join-Path $root 'src\StupratorsServer.cs')
if ($LASTEXITCODE -ne 0) { throw 'Compile failed.' }

$hash = (Get-FileHash -Algorithm SHA256 $out).Hash.ToLower()
"$hash  Install-Stuprators-Server.cmd" | Set-Content (Join-Path $root 'dist\SHA256.txt') -Encoding ASCII
"Built: $out"
"SHA-256: $hash"
"Size: $([math]::Round((Get-Item $out).Length / 1KB)) KB, $((Get-Content $out).Count) lines"
