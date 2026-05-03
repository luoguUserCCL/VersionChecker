# Version Checker with Auto Update
# Author: Super Z

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function WC($T, $C) { Write-Host $T -ForegroundColor $C -NoNewline }
function WL($T, $C) { Write-Host $T -ForegroundColor $C }

function GetOut($Cmd, $ArgStr) {
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "cmd.exe"
        $psi.Arguments = "/c `"$Cmd $ArgStr`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $out = $proc.StandardOutput.ReadToEnd()
        $out += $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        return $out
    } catch { return $null }
}

function GetPage($Url) {
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30
        return $r.Content
    } catch { return $null }
}

function GetApi($Url) {
    try { return Invoke-RestMethod -Uri $Url -TimeoutSec 30 }
    catch { return $null }
}

function CmpVer($V1, $V2) {
    $a1 = [regex]::Matches($V1, "\d+") | ForEach-Object { [int]$_.Value }
    $a2 = [regex]::Matches($V2, "\d+") | ForEach-Object { [int]$_.Value }
    $a1 = @($a1); $a2 = @($a2)
    $max = [Math]::Max($a1.Length, $a2.Length)
    for ($i = 0; $i -lt $max; $i++) {
        $n1 = if ($i -lt $a1.Length) { $a1[$i] } else { 0 }
        $n2 = if ($i -lt $a2.Length) { $a2[$i] } else { 0 }
        if ($n1 -lt $n2) { return -1 }
        if ($n1 -gt $n2) { return 1 }
    }
    return 0
}

# ==================== GitHub Proxy ====================

function ProxyUrl($Url) {
    if ($Url -match "github\.com") {
        return "https://tvv.tw/" + $Url
    }
    return $Url
}

# ==================== Download ====================

function Download-File($Url, $OutFile, $Desc) {
    WL "Downloading $Desc..." "Cyan"
    WL "  URL: $Url" "Gray"
    
    $dir = Split-Path $OutFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    
    # Remove existing file if present
    if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
    
    try {
        Add-Type -AssemblyName System.Net.Http
        $httpClient = New-Object System.Net.Http.HttpClient
        $httpClient.Timeout = [TimeSpan]::FromMinutes(30)
        $httpClient.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
        
        # Get response with headers first
        $response = $httpClient.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
        $response.EnsureSuccessStatusCode() | Out-Null
        
        $totalBytes = $response.Content.Headers.ContentLength
        if (-not $totalBytes) { $totalBytes = 0 }
        
        $stream = $response.Content.ReadAsStreamAsync().Result
        $fileStream = [System.IO.File]::Create($OutFile)
        
        $buffer = New-Object byte[] 81920
        $totalRead = 0L
        $lastUpdate = [DateTime]::Now
        $startTime = [DateTime]::Now
        $progressLine = ""
        
        while ($true) {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -eq 0) { break }
            
            $fileStream.Write($buffer, 0, $read)
            $totalRead += $read
            
            # Update progress every 300ms
            $now = [DateTime]::Now
            if (($now - $lastUpdate).TotalMilliseconds -gt 300) {
                $elapsed = ($now - $startTime).TotalSeconds
                $speed = if ($elapsed -gt 0) { $totalRead / $elapsed } else { 0 }
                
                # Build progress bar
                $barWidth = 30
                if ($totalBytes -gt 0) {
                    $pct = [math]::Min(100, [math]::Round(($totalRead / $totalBytes) * 100))
                    $filled = [math]::Round($barWidth * $pct / 100)
                    $empty = $barWidth - $filled
                    $bar = "[" + ("=" * $filled) + (" " * $empty) + "]"
                    
                    $eta = if ($speed -gt 0) { [int](($totalBytes - $totalRead) / $speed) } else { 0 }
                    $etaStr = if ($eta -gt 3600) { "{0:h\:mm\:ss}" -f [TimeSpan]::FromSeconds($eta) }
                              elseif ($eta -gt 60) { "{0:mm\:ss}" -f [TimeSpan]::FromSeconds($eta) }
                              else { "${eta}s" }
                    
                    $speedStr = if ($speed -gt 1MB) { "{0:N1} MB/s" -f ($speed / 1MB) }
                               elseif ($speed -gt 1KB) { "{0:N0} KB/s" -f ($speed / 1KB) }
                               else { "{0:N0} B/s" -f $speed }
                    
                    $readStr = if ($totalRead -gt 1MB) { "{0:N1} MB" -f ($totalRead / 1MB) }
                              else { "{0:N0} KB" -f ($totalRead / 1KB) }
                    
                    $progressLine = "  $bar $pct% | $readStr | $speedStr | ETA: $etaStr"
                } else {
                    $speedStr = if ($speed -gt 1MB) { "{0:N1} MB/s" -f ($speed / 1MB) }
                               elseif ($speed -gt 1KB) { "{0:N0} KB/s" -f ($speed / 1KB) }
                               else { "{0:N0} B/s" -f $speed }
                    $readStr = if ($totalRead -gt 1MB) { "{0:N1} MB" -f ($totalRead / 1MB) }
                              else { "{0:N0} KB" -f ($totalRead / 1KB) }
                    $progressLine = "  Downloading... $readStr | $speedStr"
                }
                
                # Clear line and print progress
                Write-Host "`r$progressLine" -NoNewline
                $lastUpdate = $now
            }
        }
        
        $fileStream.Close()
        $stream.Close()
        $httpClient.Dispose()
        
        # Clear progress line and show final result
        Write-Host "`r" -NoNewline
        Write-Host " " * 80 -NoNewline
        Write-Host "`r" -NoNewline
        
        if (Test-Path $OutFile) {
            $size = (Get-Item $OutFile).Length
            $sizeStr = if ($size -gt 1MB) { "{0:N2} MB" -f ($size / 1MB) }
                      elseif ($size -gt 1KB) { "{0:N0} KB" -f ($size / 1KB) }
                      else { "$size bytes" }
            WL "  Done: $sizeStr" "Green"
            return $true
        }
    } catch {
        Write-Host "`r" -NoNewline
        Write-Host " " * 80 -NoNewline  
        Write-Host "`r" -NoNewline
        WL "  Error: $($_.Exception.Message)" "Red"
        if (Test-Path $OutFile) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }
    }
    return $false
}

# ==================== Extract ====================

function Extract-Zip($ZipFile, $DestDir) {
    WL "Extracting $ZipFile..." "Cyan"
    
    if (-not (Test-Path $DestDir)) { New-Item -ItemType Directory -Path $DestDir -Force | Out-Null }
    
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipFile, $DestDir)
        WL "  Done" "Green"
        return $true
    } catch {
        WL "  Error: $_" "Red"
        return $false
    }
}

function Extract-7z($File, $DestDir) {
    WL "Extracting $File..." "Cyan"
    
    if (-not (Test-Path $DestDir)) { New-Item -ItemType Directory -Path $DestDir -Force | Out-Null }
    
    # Find 7z
    $sevenZip = @(
        "${env:ProgramFiles}\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        "C:\Program Files\7-Zip\7z.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    
    if (-not $sevenZip) {
        WL "  7-Zip not found, trying PowerShell expansion..." "Yellow"
        # Try tar command (Windows 10+)
        $result = cmd /c "tar -xf `"$File`" -C `"$DestDir`" 2>&1"
        if ($LASTEXITCODE -eq 0) {
            WL "  Done" "Green"
            return $true
        }
        WL "  Error: Cannot extract .7z file. Please install 7-Zip." "Red"
        return $false
    }
    
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $sevenZip
    $psi.Arguments = "x `"$File`" -o`"$DestDir`" -y"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.WaitForExit()
    
    if ($proc.ExitCode -eq 0) {
        WL "  Done" "Green"
        return $true
    }
    WL "  Error: Exit code $($proc.ExitCode)" "Red"
    return $false
}

# ==================== Environment Variables ====================

function Set-EnvVar($Name, $Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, "Machine")
    WL "  Set $Name = $Value (System)" "Green"
}

function Add-ToPath($Dir) {
    $path = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    $dirs = $path -split ";" | Where-Object { $_ -ne "" }
    
    # Remove old entries for same tool
    $dirs = $dirs | Where-Object { $_ -notlike "*$Dir*" }
    
    # Add new entry at beginning
    $newPath = $Dir + ";" + ($dirs -join ";")
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
    WL "  Updated System PATH" "Green"
}

# ==================== Version Detection ====================

# Java
function JLocal {
    $o = GetOut "java" "-version"
    if (-not $o) { return $null }
    $m = [regex]::Match($o, 'version "?(\d+(?:\.\d+)*)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function JLatest {
    $h = GetPage "https://jdk.java.net/"
    if (-not $h) { return $null }
    $m = [regex]::Match($h, 'Ready for use:.*?<a href="/(\d+)/"', 16)
    if (-not $m.Success) { return $null }
    $v = $m.Groups[1].Value
    $h2 = GetPage "https://jdk.java.net/$v/"
    if (-not $h2) { return $v }
    $m2 = [regex]::Match($h2, 'JDK\s+(\d+(?:\.\d+)+)\s+GA\s+Release', 1)
    if ($m2.Success) { return $m2.Groups[1].Value }
    return $v
}

# Python
function PLocal {
    $o = GetOut "python" "--version"
    if (-not $o) { $o = GetOut "python3" "--version" }
    if (-not $o) { return $null }
    $m = [regex]::Match($o, 'Python\s+(\d+(?:\.\d+)*)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function PLatest {
    $j = GetApi "https://api.github.com/repos/python/cpython/tags?per_page=100"
    if (-not $j) { return $null }
    foreach ($t in $j) {
        # Match stable versions: X.Y.Z format
        $m = [regex]::Match($t.name, '^v?(\d+\.\d+\.\d+)$')
        if ($m.Success) {
            return $m.Groups[1].Value
        }
    }
    return $null
}

# MinGW
function MLocal {
    $o = GetOut "g++" "--version"
    if (-not $o) { $o = GetOut "gcc" "--version" }
    if (-not $o) { return $null }
    $m = [regex]::Match($o, '\)\s*(\d+\.\d+\.\d+)', 1)
    if ($m.Success) { return $m.Groups[1].Value }
    $m = [regex]::Match($o, 'GCC\s+(\d+\.\d+\.\d+)', 1)
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function MLatest {
    $j = GetApi "https://api.github.com/repos/niXman/mingw-builds-binaries/releases/latest"
    if (-not $j) { return $null }
    $m = [regex]::Match($j.tag_name, '(\d+\.\d+\.\d+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

# Kotlin
function KLocal {
    $o = GetOut "kotlin" "-version"
    if (-not $o) { $o = GetOut "kotlinc" "-version" }
    if (-not $o) { return $null }
    $m = [regex]::Match($o, 'Kotlin\s+(?:version\s+)?(\d+\.\d+(?:\.\d+)?)', 1)
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function KLatest {
    $j = GetApi "https://api.github.com/repos/JetBrains/kotlin/releases/latest"
    if (-not $j) { return $null }
    $m = [regex]::Match($j.tag_name, 'v?(\d+\.\d+(?:\.\d+)?)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

# PHP
function PhLocal {
    $o = GetOut "php" "-v"
    if (-not $o) { return $null }
    $m = [regex]::Match($o, 'PHP\s+(\d+\.\d+(?:\.\d+)?)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function PhLatest {
    $j = GetApi "https://api.github.com/repos/php/php-src/releases/latest"
    if (-not $j) { return $null }
    $m = [regex]::Match($j.tag_name, 'php-?(\d+\.\d+(?:\.\d+)?)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

# ==================== Update Functions ====================

function Ask-InstallDir($Tool, $DefaultDir) {
    Write-Host ""
    WL "Install location for $Tool" "Cyan"
    WL "  Default: $DefaultDir" "Gray"
    $custom = Read-Host "  Press Enter for default, or input custom path"
    if ($custom -eq "") {
        return $DefaultDir
    }
    # Expand environment variables if present
    $custom = [Environment]::ExpandEnvironmentVariables($custom)
    return $custom
}

function Update-Python($Version) {
    WL "`n=== Updating Python to $Version ===" "Cyan"

    $defaultDest = "$env:LOCALAPPDATA\Programs\Python\Python$Version"
    $dest = Ask-InstallDir "Python" $defaultDest

    # Use full Windows installer instead of embed version
    # The embed version lacks encodings module in python3xx.zip
    $url = "https://mirrors.aliyun.com/python-release/windows/python-$Version-amd64.exe"
    $exe = "$env:TEMP\python-$Version-amd64.exe"

    if (-not (Download-File $url $exe "Python $Version installer")) { return $false }

    # Verify downloaded file size (full installer should be at least 20MB)
    $exeInfo = Get-Item $exe -ErrorAction SilentlyContinue
    if (-not $exeInfo -or $exeInfo.Length -lt 20MB) {
        WL "ERROR: Downloaded file is too small ($([math]::Round($exeInfo.Length/1MB, 2)) MB)" "Red"
        WL "This version may not exist on the mirror or the download failed." "Red"
        WL "Please check if Python $Version is a valid release." "Yellow"
        Remove-Item $exe -Force -ErrorAction SilentlyContinue
        return $false
    }

    WL "Running Python installer..." "Cyan"
    WL "  Installing to: $dest" "Gray"
    
    # Check if destination is outside user directory (may need admin)
    $isCustomPath = $dest -notlike "$env:LOCALAPPDATA\*"
    if ($isCustomPath) {
        WL "  Custom path detected - may require administrator privileges" "Yellow"
    }
    
    # Run installer with custom path
    # InstallAllUsers=1 - system-wide installation (for custom paths)
    # TargetDir= - custom installation path
    # PrependPath=0 - we handle PATH manually
    # Include_pip=1 - include pip
    $installArgs = @(
        "/quiet",
        "InstallAllUsers=1",
        "TargetDir=`"$dest`"",
        "PrependPath=0",
        "Include_pip=1",
        "Include_test=0",
        "Include_doc=0",
        "Include_dev=0",
        "Include_tcltk=1",
        "Include_launcher=1"
    ) -join " "

    WL "  Running: $exe $installArgs" "Gray"
    
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = $installArgs
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.WaitForExit()
    
    $exitCode = $proc.ExitCode
    WL "  Installer exit code: $exitCode" "Gray"
    
    # Give installer time to finish file operations
    Start-Sleep -Seconds 3
    
    # Clean up installer
    Remove-Item $exe -Force -ErrorAction SilentlyContinue

    # Check if installation directory exists
    $pythonExe = $null
    $actualDest = $null
    
    if (Test-Path $dest) {
        $pythonExe = "$dest\python.exe"
        $actualDest = $dest
    } else {
        WL "  Target directory not found, searching for actual installation..." "Yellow"
        
        # Extract version parts for path matching
        $vParts = $Version.Split('.')
        $vMajor = $vParts[0]  # e.g., "3"
        $vMinor = $vParts[1]  # e.g., "14"
        $vShort = "$vMajor$vMinor"  # e.g., "314" for "3.14.4"
        
        WL "  Version parsed: $Version -> short: $vShort" "Gray"
        
        # Check common installation locations
        $possibleLocations = @(
            $dest,  # User-specified path first
            "D:\Compilers\Python$vShort",  # D:\Compilers\Python314
            "D:\Python$vShort",
            "C:\Python$vShort",
            "$env:LOCALAPPDATA\Programs\Python\Python$vShort",
            "$env:LOCALAPPDATA\Programs\Python\Python$Version",
            "${env:ProgramFiles}\Python$vShort",
            "${env:ProgramFiles}\Python$Version",
            "D:\Python$Version",
            "D:\Compilers\Python$Version"
        ) | Where-Object { $_ -ne $null } | Select-Object -Unique
        
        WL "  Checking locations: $($possibleLocations -join ', ')" "Gray"
        
        foreach ($loc in $possibleLocations) {
            WL "    Checking: $loc" "Gray"
            if (Test-Path $loc) {
                $testExe = "$loc\python.exe"
                if (Test-Path $testExe) {
                    WL "  Found Python at: $loc" "Green"
                    $pythonExe = $testExe
                    $actualDest = $loc
                    break
                }
            }
        }
        
        # Try to find Python in registry
        if (-not $pythonExe) {
            try {
                $regPath = "HKLM:\SOFTWARE\Python\PythonCore\$Version\InstallPath"
                $regPathUser = "HKCU:\SOFTWARE\Python\PythonCore\$Version\InstallPath"
                
                $installPath = $null
                if (Test-Path $regPath) {
                    $installPath = (Get-ItemProperty $regPath -ErrorAction SilentlyContinue).'(default)'
                } elseif (Test-Path $regPathUser) {
                    $installPath = (Get-ItemProperty $regPathUser -ErrorAction SilentlyContinue).'(default)'
                }
                
                if ($installPath -and (Test-Path $installPath)) {
                    $testExe = Join-Path $installPath "python.exe"
                    if (Test-Path $testExe) {
                        WL "  Found Python via registry: $installPath" "Green"
                        $pythonExe = $testExe
                        $actualDest = $installPath
                    }
                }
            } catch { }
        }
        
        # Try searching for python.exe
        if (-not $pythonExe) {
            WL "  Searching for python.exe (this may take a moment)..." "Gray"
            $found = Get-Command python.exe -ErrorAction SilentlyContinue
            if ($found) {
                $foundDir = Split-Path $found.Source -Parent
                # Check if it's the right version
                $vCheck = & $found.Source -c "import sys; print(sys.version)" 2>$null
                if ($vCheck -match $Version) {
                    WL "  Found Python in PATH: $foundDir" "Green"
                    $pythonExe = $found.Source
                    $actualDest = $foundDir
                }
            }
        }
    }
    
    if (-not $pythonExe -or -not (Test-Path $pythonExe)) {
        WL "ERROR: Python installation not found after installer ran" "Red"
        WL "  The installer may have failed silently." "Yellow"
        WL "  Try running the installer manually: $exe" "Yellow"
        return $false
    }

    # Test Python installation
    WL "Testing Python installation..." "Gray"
    $testPsi = New-Object System.Diagnostics.ProcessStartInfo
    $testPsi.FileName = $pythonExe
    $testPsi.Arguments = "-c `"import sys; print('Python', sys.version); import encodings; print('encodings OK')`""
    $testPsi.UseShellExecute = $false
    $testPsi.CreateNoWindow = $true
    $testPsi.RedirectStandardOutput = $true
    $testPsi.RedirectStandardError = $true
    $testPsi.WorkingDirectory = $actualDest
    
    $testProc = [System.Diagnostics.Process]::Start($testPsi)
    $testOut = $testProc.StandardOutput.ReadToEnd()
    $testErr = $testProc.StandardError.ReadToEnd()
    $testProc.WaitForExit()
    
    if ($testProc.ExitCode -ne 0) {
        WL "ERROR: Python test failed!" "Red"
        WL "  STDOUT: $testOut" "Gray"
        WL "  STDERR: $testErr" "Red"
        return $false
    }
    WL "Python test passed!" "Green"
    WL "  $testOut" "Gray"

    # Check pip
    WL "Checking pip..." "Gray"
    $pipTest = New-Object System.Diagnostics.ProcessStartInfo
    $pipTest.FileName = $pythonExe
    $pipTest.Arguments = "-c `"import pip; print('pip', pip.__version__)`""
    $pipTest.UseShellExecute = $false
    $pipTest.CreateNoWindow = $true
    $pipTest.RedirectStandardOutput = $true
    $pipTest.RedirectStandardError = $true
    $pipTest.WorkingDirectory = $actualDest
    
    $pipProc = [System.Diagnostics.Process]::Start($pipTest)
    $pipOut = $pipProc.StandardOutput.ReadToEnd()
    $pipProc.WaitForExit()
    
    if ($pipProc.ExitCode -eq 0) {
        WL "pip installed: $pipOut" "Green"
    } else {
        WL "pip not found, installing..." "Yellow"
        
        # Download and run get-pip.py
        $getPipFile = "$actualDest\get-pip.py"
        $getPipUrl = "https://tvv.tw/https://github.com/pypa/get-pip/raw/refs/heads/main/public/get-pip.py"
        
        if (Download-File $getPipUrl $getPipFile "get-pip.py") {
            $gpPsi = New-Object System.Diagnostics.ProcessStartInfo
            $gpPsi.FileName = $pythonExe
            $gpPsi.Arguments = "`"$getPipFile`" --quiet"
            $gpPsi.UseShellExecute = $false
            $gpPsi.CreateNoWindow = $true
            $gpPsi.WorkingDirectory = $actualDest
            
            $gpProc = [System.Diagnostics.Process]::Start($gpPsi)
            $gpProc.WaitForExit()
            
            if ($gpProc.ExitCode -eq 0) {
                WL "pip installed successfully!" "Green"
            }
            Remove-Item $getPipFile -Force -ErrorAction SilentlyContinue
        }
    }

    # Create pip.ini for Chinese mirror
    $pipDir = "$env:APPDATA\pip"
    if (-not (Test-Path $pipDir)) { New-Item -ItemType Directory -Path $pipDir -Force | Out-Null }
    $pipIni = "$pipDir\pip.ini"
    $pipContent = @"
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn
"@
    Set-Content $pipIni $pipContent -Encoding UTF8
    WL "Configured pip to use Tsinghua mirror" "Green"

    # Set environment variable
    Set-EnvVar "PYTHON_HOME" $actualDest

    WL "Python $Version installation complete!" "Green"
    WL "  Installed to: $actualDest" "Green"
    return $true
}

function Update-Java($Version) {
    WL "`n=== Updating Java to $Version ===" "Cyan"
    
    # Get major version for URL
    $vMajor = $Version.Split('.')[0]
    
    $defaultDest = "$env:LOCALAPPDATA\Programs\Java\jdk-$Version"
    $dest = Ask-InstallDir "Java" $defaultDest
    
    # Get download URL from jdk.java.net
    WL "Fetching download URL from jdk.java.net/$vMajor/..." "Gray"
    $h = GetPage "https://jdk.java.net/$vMajor/"
    if (-not $h) { WL "Failed to get download page" "Red"; return $false }
    
    # Find Windows/x64 download link - look for href after "Windows/x64" text
    # Pattern: find "Windows/x64" or "Windows&#x2F;x64" then capture the following href
    $patterns = @(
        'Windows[/&#x2F;]+x64[^>]*href="([^"]+\.zip)"',
        'Windows/x64[^>]*href="([^"]+\.zip)"',
        'href="(https://download\.java\.net/[^"]*windows-x64[^"]*\.zip)"'
    )
    
    $url = $null
    foreach ($p in $patterns) {
        $m = [regex]::Match($h, $p, 1)
        if ($m.Success) {
            $url = $m.Groups[1].Value
            # Handle relative URLs
            if ($url -match "^/") {
                $url = "https://jdk.java.net" + $url
            }
            WL "Found download URL: $url" "Green"
            break
        }
    }
    
    if (-not $url) {
        WL "Download URL not found on page" "Red"
        return $false
    }
    
    $zip = "$env:TEMP\openjdk-$Version-windows-x64.zip"
    
    if (-not (Download-File $url $zip "Java $Version")) { return $false }
    
    # Remove old installation
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    
    $extractDir = "$env:TEMP\jdk-extract"
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    
    if (-not (Extract-Zip $zip $extractDir)) { return $false }
    
    # Move extracted content
    $inner = Get-ChildItem $extractDir -Directory | Select-Object -First 1
    Move-Item $inner.FullName $dest -Force
    Remove-Item $extractDir -Recurse -Force
    Remove-Item $zip -Force
    
    # Set environment (only HOME, not PATH)
    Set-EnvVar "JAVA_HOME" $dest
    
    return $true
}

function Update-Kotlin($Version) {
    WL "`n=== Updating Kotlin to $Version ===" "Cyan"
    
    $defaultDest = "$env:LOCALAPPDATA\Programs\Kotlin\kotlinc-$Version"
    $dest = Ask-InstallDir "Kotlin" $defaultDest
    
    # Use GitHub proxy (will auto-speedtest)
    $baseUrl = "https://github.com/JetBrains/kotlin/releases/download/v$Version/kotlin-compiler-$Version.zip"
    $url = ProxyUrl $baseUrl
    $zip = "$env:TEMP\kotlin-compiler-$Version.zip"
    
    if (-not (Download-File $url $zip "Kotlin $Version")) { return $false }
    
    # Remove old installation
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    
    $extractDir = "$env:TEMP\kotlin-extract"
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    
    if (-not (Extract-Zip $zip $extractDir)) { return $false }
    
    # Move extracted content
    $inner = Get-ChildItem $extractDir -Directory | Where-Object { $_.Name -like "kotlinc*" } | Select-Object -First 1
    if ($inner) {
        Move-Item $inner.FullName $dest -Force
    } else {
        Move-Item $extractDir $dest -Force
    }
    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $zip -Force
    
    # Set environment (only HOME, not PATH)
    Set-EnvVar "KOTLIN_HOME" $dest
    
    return $true
}

function Update-MinGW($Version) {
    WL "`n=== Updating MinGW to $Version ===" "Cyan"
    
    $defaultDest = "$env:LOCALAPPDATA\Programs\MinGW\mingw64"
    $dest = Ask-InstallDir "MinGW" $defaultDest
    
    # Get release info
    $j = GetApi "https://api.github.com/repos/niXman/mingw-builds-binaries/releases/latest"
    if (-not $j) { WL "Failed to get release info" "Red"; return $false }
    
    # Find x86_64 win32 seh msvcrt asset
    $asset = $j.assets | Where-Object { $_.name -match "x86_64-.+-win32-seh-msvcrt.+\.7z" } | Select-Object -First 1
    if (-not $asset) {
        WL "Download asset not found" "Red"
        return $false
    }
    
    $url = ProxyUrl $asset.browser_download_url
    $file = "$env:TEMP\$($asset.name)"
    
    if (-not (Download-File $url $file "MinGW $Version")) { return $false }
    
    # Remove old installation
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    
    $extractDir = "$env:TEMP\mingw-extract"
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    
    if (-not (Extract-7z $file $extractDir)) { return $false }
    
    # Move extracted content
    $inner = Get-ChildItem $extractDir -Directory | Select-Object -First 1
    if ($inner) {
        Move-Item $inner.FullName $dest -Force
    } else {
        Move-Item "$extractDir\mingw64" $dest -Force
    }
    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $file -Force
    
    # Set environment (only HOME, not PATH)
    Set-EnvVar "MINGW_HOME" $dest
    
    return $true
}

function Update-PHP($Version) {
    WL "`n=== Updating PHP to $Version ===" "Cyan"
    WL "Downloading pre-built Windows binaries..." "Gray"
    
    $defaultDest = "$env:LOCALAPPDATA\Programs\PHP\php-$Version"
    $dest = Ask-InstallDir "PHP" $defaultDest
    
    # Use pre-built Windows binaries
    $vShort = $Version -replace '\.\d+$', ''
    $url = "https://windows.php.net/downloads/releases/php-$Version-Win32-vs16-x64.zip"
    
    $zip = "$env:TEMP\php-$Version-Win32-x64.zip"
    
    if (-not (Download-File $url $zip "PHP $Version")) {
        # Try archive
        $url = "https://windows.php.net/downloads/releases/archive/php-$Version-Win32-vs16-x64.zip"
        if (-not (Download-File $url $zip "PHP $Version")) { return $false }
    }
    
    # Remove old installation
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    
    if (-not (Extract-Zip $zip $dest)) { return $false }
    
    Remove-Item $zip -Force
    
    # Set environment (only HOME, not PATH)
    Set-EnvVar "PHP_HOME" $dest
    
    return $true
}

# ==================== Main ====================

function Main {
    WL "========================================" "Cyan"
    WL "Development Environment Version Checker" "Cyan"
    WL "========================================" "Cyan"
    Write-Host ""
    
    $tools = @(
        @{ N = "Java"; Local = { JLocal }; Latest = { JLatest }; Update = { param($v) Update-Java $v } }
        @{ N = "Python"; Local = { PLocal }; Latest = { PLatest }; Update = { param($v) Update-Python $v } }
        @{ N = "MinGW/GCC"; Local = { MLocal }; Latest = { MLatest }; Update = { param($v) Update-MinGW $v } }
        @{ N = "Kotlin"; Local = { KLocal }; Latest = { KLatest }; Update = { param($v) Update-Kotlin $v } }
        @{ N = "PHP"; Local = { PhLocal }; Latest = { PhLatest }; Update = { param($v) Update-PHP $v } }
    )
    
    $results = @()
    
    # Check versions
    for ($i = 0; $i -lt $tools.Count; $i++) {
        $t = $tools[$i]
        Write-Host "Checking " -NoNewline
        WC $t.N "Cyan"
        Write-Host "... " -NoNewline
        
        $loc = & $t.Local
        $lat = & $t.Latest
        $cmp = if ($loc -and $lat) { CmpVer $loc $lat } else { -99 }
        
        $results += @{
            Tool = $t
            Local = $loc
            Latest = $lat
            Cmp = $cmp
        }
        
        if (-not $loc) { WL "X Not installed" "Red" }
        elseif (-not $lat) { WL "? Cannot check" "Yellow" }
        elseif ($cmp -ge 0) { WL "OK" "Green" }
        else {
            WC "! " "Yellow"
            Write-Host "(Update: " -NoNewline
            WC $lat "Blue"
            Write-Host ")"
        }
    }
    
    Write-Host ""
    $sep = "=" * 60
    Write-Host $sep
    WL "Version Report" "Cyan"
    Write-Host $sep
    Write-Host ""
    
    $needUpdate = @()
    
    foreach ($r in $results) {
        WC "[$($r.Tool.N)]" "Cyan"
        Write-Host ""
        Write-Host "  Latest:  " -NoNewline
        if ($r.Latest) { WL $r.Latest "Blue" } else { WL "Unknown" "Gray" }
        Write-Host "  Local:   " -NoNewline
        if (-not $r.Local) { WL "Not installed" "Red" }
        elseif ($r.Cmp -ge 0) { WL $r.Local "Green" }
        else { WL $r.Local "Yellow" }
        Write-Host "  Status:  " -NoNewline
        if (-not $r.Local) { WL "X Not installed" "Red" }
        elseif (-not $r.Latest) { WL "? Cannot check" "Yellow" }
        elseif ($r.Cmp -ge 0) { WL "OK Up to date" "Green" }
        else {
            WL "! Need update" "Yellow"
            $needUpdate += $r
        }
        Write-Host ""
    }
    
    Write-Host $sep
    Write-Host "Total: $($results.Count) items"
    Write-Host "  Need update: " -NoNewline
    if ($needUpdate.Count -gt 0) { WL $needUpdate.Count "Yellow" } else { WL $needUpdate.Count "Green" }
    Write-Host $sep
    
    # Ask for updates
    if ($needUpdate.Count -gt 0) {
        Write-Host ""
        WL "The following tools need updates:" "Yellow"
        foreach ($r in $needUpdate) {
            Write-Host "  - $($r.Tool.N): $($r.Local) -> $($r.Latest)"
        }
        Write-Host ""
        
        foreach ($r in $needUpdate) {
            Write-Host ""
            $ans = Read-Host "Update $($r.Tool.N) to $($r.Latest)? (Y/n)"
            if ($ans -eq "" -or $ans -eq "Y" -or $ans -eq "y") {
                $success = & $r.Tool.Update $r.Latest
                if ($success) {
                    WL "$($r.Tool.N) updated successfully!" "Green"
                    WL "Please restart your terminal to apply changes." "Yellow"
                } else {
                    WL "Failed to update $($r.Tool.N)" "Red"
                }
            } else {
                WL "Skipped $($r.Tool.N)" "Gray"
            }
        }
    }
    
    Write-Host ""
    WL "Done." "Green"
}

Main
