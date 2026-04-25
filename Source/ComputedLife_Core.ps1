# Load WPF and Windows Forms assemblies for GUI
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# Call Windows API to set DPI awareness for high-resolution displays
$sig = @'
[DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
'@
$type = Add-Type -MemberDefinition $sig -Name "Win32Utils" -Namespace "DPI" -PassThru
$type::SetProcessDPIAware() | Out-Null

# Embed C# code for generating high-quality gradient background with blue noise dithering
$csharpCode = @"
using System;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

public class DitherEngine {
    private static float GetBlueNoise(int x, int y) {
        uint seed = (uint)(x * 0x1F1F1F1F ^ y * 0x7F7F7F7F);
        seed ^= seed << 13;
        seed ^= seed >> 17;
        seed ^= seed << 5;
        uint v = seed;
        v = ((v >> 1) & 0x55555555) | ((v & 0x55555555) << 1);
        v = ((v >> 2) & 0x33333333) | ((v & 0x33333333) << 2);
        v = ((v >> 4) & 0x0F0F0F0F) | ((v & 0x0F0F0F0F) << 4);
        v = ((v >> 8) & 0x00FF00FF) | ((v & 0x00FF00FF) << 8);
        v = ( v >> 16 ) | ( v << 16);
        return (float)v / (float)uint.MaxValue - 0.5f;
    }

    public static BitmapSource GenerateBlueNoiseGradient(int width, int height, Color inner, Color outer) {
        byte[] pixels = new byte[width * height * 4];
        float centerX = width * 0.5f;
        float centerY = height * 0.4f; 
        float maxRadius = (float)Math.Sqrt(width * width + height * height) * 0.65f;

        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                float dx = x - centerX;
                float dy = y - centerY;
                float dist = (float)Math.Sqrt(dx*dx + dy*dy);
                float ratio = Math.Min(1.0f, dist / maxRadius);
                ratio = ratio * ratio * (3 - 2 * ratio); 

                float idealR = inner.R + (outer.R - inner.R) * ratio;
                float idealG = inner.G + (outer.G - inner.G) * ratio;
                float idealB = inner.B + (outer.B - inner.B) * ratio;

                float noise = GetBlueNoise(x, y);
                float noiseIntensity = 6.0f; 
                float ditheredR = idealR + noise * noiseIntensity;
                float ditheredG = idealG + noise * noiseIntensity;
                float ditheredB = idealB + noise * noiseIntensity;

                byte outR = (byte)Math.Max(0, Math.Min(255, Math.Round(ditheredR)));
                byte outG = (byte)Math.Max(0, Math.Min(255, Math.Round(ditheredG)));
                byte outB = (byte)Math.Max(0, Math.Min(255, Math.Round(ditheredB)));

                int idx = (y * width + x) * 4;
                pixels[idx] = outB; pixels[idx + 1] = outG; pixels[idx + 2] = outR; pixels[idx + 3] = 255; 
            }
        }
        return BitmapSource.Create(width, height, 96, 96, PixelFormats.Bgra32, null, pixels, width * 4);
    }
}
"@
Add-Type -TypeDefinition $csharpCode -ReferencedAssemblies "PresentationCore", "PresentationFramework", "WindowsBase"

# Define config file path (Config.json in same directory as this script)
$configPath = "$PSScriptRoot\Config.json"

# Function: Validate time string format (HH:mm)
function Test-TimeFormat {
    param([string]$timeStr)
    
    if ([string]::IsNullOrWhiteSpace($timeStr)) { return $false }
    
    # Remove 24:00 special handling
    $cleanTime = $timeStr -replace "24:00", "00:00"
    
    # Check format is HH:mm
    if ($cleanTime -notmatch '^\d{1,2}:\d{2}$') { return $false }
    
    # Split hour and minute
    $parts = $cleanTime.Split(':')
    if ($parts.Count -ne 2) { return $false }
    
    try {
        $hour = [int]$parts[0]
        $minute = [int]$parts[1]
        
    # Validate hour and minute range
        if ($hour -lt 0 -or $hour -gt 23) { return $false }
        if ($minute -lt 0 -or $minute -gt 59) { return $false }
        
        return $true
    }
    catch {
        return $false
    }
}

# Function: Read and parse Config.json with validation
function Get-AppConfiguration {
    $def = @{ 
        RestPeriods = @(@{ Start = "00:00"; End = "00:00" }); 
        Warnings    = @(@{ Text = "警告：5分钟后，你的电脑将变回一块发光的砖头。"; Button = "趁还没变砖赶紧关了" }) 
    }
    
    $script:ConfigError = $null
    $script:ConfigPath = $configPath
    $script:TimeParseErrors = @()
    
    if (-not (Test-Path $configPath)) {
        $script:ConfigError = "配置文件不存在: $configPath"
        return $def
    }
    
    try {
        $rawContent = Get-Content $configPath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($rawContent)) {
            $script:ConfigError = "配置文件为空"
            return $def
        }
        
        $config = $rawContent | ConvertFrom-Json
        
        # Validate config structure
        if ($null -eq $config.RestPeriods -or $null -eq $config.Warnings) {
            $script:ConfigError = "配置文件结构不完整，缺少 RestPeriods 或 Warnings 字段"
            return $def
        }
        
        if ($config.RestPeriods.Count -eq 0) {
            $script:ConfigError = "RestPeriods 不能为空"
            return $def
        }
        
        if ($config.Warnings.Count -eq 0) {
            $script:ConfigError = "Warnings 不能为空"
            return $def
        }
        
        # Validate time format and enabled field
        foreach ($period in $config.RestPeriods) {
            if ($null -ne $period.Enabled) {
                if ($period.Enabled -notin @($true, $false)) {
                    $script:TimeParseErrors += "使能字段格式错误: $($period.Label) 的 Enabled 必须是 true 或 false"
                }
            }
            
            if ($null -ne $period.Start -and -not (Test-TimeFormat $period.Start)) {
                $script:TimeParseErrors += "无效时间格式: $($period.Start)"
            }
            if ($null -ne $period.End -and -not (Test-TimeFormat $period.End)) {
                $script:TimeParseErrors += "无效时间格式: $($period.End)"
            }
            
            # Validate date range
            if ($null -ne $period.DateRange) {
                try {
                    $startDate = [DateTime]::Parse($period.DateRange.Start)
                    $endDate = [DateTime]::Parse($period.DateRange.End)
                    if ($startDate -gt $endDate) {
                        $script:TimeParseErrors += "日期范围错误: 开始日期晚于结束日期"
                    }
                }
                catch {
                    $script:TimeParseErrors += "日期格式错误: $($period.DateRange.Start) 或 $($period.DateRange.End)"
                }
            }
        }
        
        return $config
    }
    catch {
        $script:ConfigError = "JSON 解析错误: $($_.Exception.Message)"
        return $def
    }
}

# Function: Get Windows theme accent color from registry
function Get-SystemThemeColor {
    try {
        $reg = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "AccentColor" -ErrorAction SilentlyContinue
        $c = $reg.AccentColor
        return [System.Windows.Media.Color]::FromArgb(255, ($c -band 0xFF), (($c -shr 8) -band 0xFF), (($c -shr 16) -band 0xFF))
    }
    catch { 
        return [System.Windows.Media.Colors]::DodgerBlue 
    }
}

# Function: Manually pump WPF event loop to prevent UI freeze
function Do-WpfEvents {
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [System.Action] { $frame.Continue = $false }
    ) | Out-Null
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

# Function: Create fullscreen overlay window for rest periods
function New-OverlayForm {
    param([double]$Opacity = 1.0, [bool]$HideCursor = $true)
    $themeColor = Get-SystemThemeColor
    $win = New-Object System.Windows.Window
    $win.WindowStyle = [System.Windows.WindowStyle]::None
    $win.AllowsTransparency = $true
    $win.WindowState = [System.Windows.WindowState]::Maximized
    $win.Topmost = $true
    $win.ShowInTaskbar = $false
    $win.Opacity = $Opacity
    if ($HideCursor) { $win.Cursor = [System.Windows.Input.Cursors]::None }

    $sw = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $sh = [System.Windows.SystemParameters]::PrimaryScreenHeight
    $glowColor = [System.Windows.Media.Color]::FromArgb(255, $themeColor.R, $themeColor.G, $themeColor.B)
    $abyssColor = [System.Windows.Media.Color]::FromArgb(255, 6, 6, 12)
    
    $ditheredBitmap = [DitherEngine]::GenerateBlueNoiseGradient([int]$sw, [int]$sh, $glowColor, $abyssColor)
    $imageBrush = New-Object System.Windows.Media.ImageBrush($ditheredBitmap)
    $imageBrush.Stretch = [System.Windows.Media.Stretch]::Fill
    $win.Background = $imageBrush
    return $win
}

# Function: Show warning popup before rest period
function Show-WarningMessage {
    param([string]$message, [string]$buttonText, [double]$timeoutSeconds = 0)

    $win = New-OverlayForm -Opacity 0 -HideCursor $false
    
    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.VerticalAlignment = "Center"
    
    $txt = New-Object System.Windows.Controls.TextBlock
    $txt.Text = $message
    $txt.Foreground = [System.Windows.Media.Brushes]::White
    $txt.FontSize = 28
    $txt.TextAlignment = "Center"
    $txt.TextWrapping = "Wrap"
    $txt.Margin = "50,0,50,60"
    $txt.FontFamily = "Microsoft YaHei UI Light"
    
    $btnContainer = New-Object System.Windows.Controls.Border
    $btnContainer.Width = 350
    $btnContainer.Height = 65
    $btnContainer.BorderThickness = 1
    $btnContainer.BorderBrush = [System.Windows.Media.Brushes]::White
    $btnContainer.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(10, 255, 255, 255))
    $btnContainer.Cursor = [System.Windows.Input.Cursors]::Hand

    $btnTxt = New-Object System.Windows.Controls.TextBlock
    $btnTxt.Text = "> $buttonText <"
    $btnTxt.Foreground = [System.Windows.Media.Brushes]::White
    $btnTxt.FontSize = 18
    $btnTxt.VerticalAlignment = "Center"
    $btnTxt.HorizontalAlignment = "Center"
    $btnTxt.FontFamily = "Consolas, Microsoft YaHei UI"

    $btnContainer.Child = $btnTxt

    $btnContainer.Add_MouseEnter({ $btnContainer.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(60, 255, 255, 255)) })
    $btnContainer.Add_MouseLeave({ $btnContainer.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(10, 255, 255, 255)) })
    $btnContainer.Add_MouseDown({
            $anim = New-Object System.Windows.Media.Animation.DoubleAnimation(0, [TimeSpan]::FromMilliseconds(150))
            $anim.Add_Completed({ $win.Close() })
            $win.BeginAnimation([System.Windows.Window]::OpacityProperty, $anim)
        })

    $stack.Children.Add($txt) | Out-Null
    $stack.Children.Add($btnContainer) | Out-Null
    $win.Content = $stack

    # Add fade-in animation: transition from transparent to target opacity after content renders
    $win.Add_ContentRendered({
        $fadeIn = New-Object System.Windows.Media.Animation.DoubleAnimation(0, 0.85, [TimeSpan]::FromMilliseconds(300))
        $win.BeginAnimation([System.Windows.Window]::OpacityProperty, $fadeIn)
    })

    if ($timeoutSeconds -gt 0) {
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds($timeoutSeconds)
        $timer.Add_Tick({
            $timer.Stop()
            $win.Close()
        })
        $timer.Start()
        $win.Add_Closed({
            if ($null -ne $timer) { $timer.Stop() }
        })
    }

    $win.ShowDialog() | Out-Null
}

# Function: Calculate next lock, unlock, and warn times based on config
function Get-ScheduleState {
    param([DateTime]$Now, $Config)

    $periods = @()

    if ($null -ne $Config.RestPeriods) {
        foreach ($period in $Config.RestPeriods) {
            if ($null -ne $period.Enabled -and -not $period.Enabled) { continue }
            if ([string]::IsNullOrWhiteSpace($period.Start) -or [string]::IsNullOrWhiteSpace($period.End)) { continue }

            $sRaw = $period.Start -replace "24:00", "00:00"
            $eRaw = $period.End -replace "24:00", "00:00"
            if ($sRaw -eq $eRaw -and $sRaw -ne "") { continue }

            try {
                $sP = $sRaw.Split(':'); $eP = $eRaw.Split(':')
                $sH = [int]$sP[0]; $sM = [int]$sP[1]
                $eH = [int]$eP[0]; $eM = [int]$eP[1]

                # Generate instances from Yesterday to Next 7 days to cover all cross-day rules
                for ($i = -1; $i -le 7; $i++) {
                    $day = $Now.Date.AddDays($i)

                    if ($null -ne $period.DaysOfWeek -and $period.DaysOfWeek.Count -gt 0) {
                        if ($period.DaysOfWeek -notcontains $day.DayOfWeek.ToString()) { continue }
                    }

                    $sT = $day.AddHours($sH).AddMinutes($sM)
                    $eT = $day.AddHours($eH).AddMinutes($eM)

                    if ($sT -gt $eT) {
                        $eT = $eT.AddDays(1)
                    }

                    if ($null -ne $period.DateRange) {
                        $rangeStart = [DateTime]::Parse($period.DateRange.Start).Date
                        $rangeEnd = [DateTime]::Parse($period.DateRange.End).Date.AddDays(1).AddTicks(-1)
                        if ($eT -lt $rangeStart -or $sT -gt $rangeEnd) { continue }
                    }

                    $periods += [PSCustomObject]@{ Start = $sT; End = $eT }
                }
            }
            catch { continue }
        }
    }

    # Merge overlapping intervals
    $merged = @()
    if ($periods.Count -gt 0) {
        $periods = $periods | Sort-Object Start
        foreach ($p in $periods) {
            if ($merged.Count -eq 0) {
                $merged += $p
            } else {
                $last = $merged[-1]
                if ($p.Start -le $last.End) {
                    if ($p.End -gt $last.End) {
                        $last.End = $p.End
                    }
                } else {
                    $merged += $p
                }
            }
        }
    }

    $isRestricted = $false
    $nextLock = [DateTime]::MaxValue
    $nextUnlock = [DateTime]::MaxValue
    $nextWarn = [DateTime]::MaxValue

    foreach ($p in $merged) {
        if ($Now -ge $p.Start -and $Now -lt $p.End) {
            $isRestricted = $true
            $nextUnlock = $p.End
        } elseif ($Now -lt $p.Start) {
            $nextLock = $p.Start
            $warnT = $p.Start.AddMinutes(-5)
            $nextWarn = if ($warnT -le $Now) { $Now } else { $warnT }
            break
        }
    }

    return [PSCustomObject]@{
        IsRestricted = $isRestricted
        NextLock     = $nextLock
        NextUnlock   = $nextUnlock
        NextWarn     = $nextWarn
    }
}

# Function: Display current monitor status in console
function Show-StatusBoard {
    param([bool]$IsRestricted, $Schedule)
    Clear-Host
    Write-Host "───────────────────────────────────────────" -ForegroundColor Gray
    Write-Host "|       " -ForegroundColor Gray -NoNewline
    Write-Host "[ COMPUTED LIFE : MONITOR ]" -ForegroundColor Yellow -NoNewline
    Write-Host "       |" -ForegroundColor Gray
    Write-Host "───────────────────────────────────────────" -ForegroundColor Gray
    Write-Host "|        >> 内部 Tick : " -ForegroundColor Gray -NoNewline
    Write-Host "$(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Magenta -NoNewline
    Write-Host "          |" -ForegroundColor Gray
    Write-Host "|        >> 内部状态  : " -ForegroundColor Gray -NoNewline
    if ($IsRestricted) { 
        Write-Host "锁定模式" -ForegroundColor Red -NoNewline 
    }
    else { 
        Write-Host "解锁模式" -ForegroundColor Green -NoNewline 
    }
    Write-Host "          |" -ForegroundColor Gray
    
    if ($null -ne $Schedule) {
        if ($IsRestricted -and $Schedule.NextUnlock -ne [DateTime]::MaxValue) {
            Write-Host "|        >> 下次解锁  : " -ForegroundColor Gray -NoNewline
            Write-Host "$($Schedule.NextUnlock.ToString('MM-dd HH:mm:ss'))" -ForegroundColor Cyan -NoNewline
            Write-Host "    |" -ForegroundColor Gray
        } elseif (-not $IsRestricted -and $Schedule.NextLock -ne [DateTime]::MaxValue) {
            Write-Host "|        >> 下次锁定  : " -ForegroundColor Gray -NoNewline
            Write-Host "$($Schedule.NextLock.ToString('MM-dd HH:mm:ss'))" -ForegroundColor Cyan -NoNewline
            Write-Host "    |" -ForegroundColor Gray
        }
    }

    # Show config status
    if ($script:ConfigError) {
        Write-Host "|        >> 配置状态  : " -ForegroundColor Gray -NoNewline
        Write-Host "有错误" -ForegroundColor Red -NoNewline
        Write-Host "              |" -ForegroundColor Gray
        Write-Host "|        >> 错误详情  : " -ForegroundColor Gray -NoNewline
        Write-Host $script:ConfigError -ForegroundColor Red -NoNewline
        Write-Host " |" -ForegroundColor Gray
    }
    else {
        Write-Host "|        >> 配置状态  : " -ForegroundColor Gray -NoNewline
        Write-Host "正常" -ForegroundColor Green -NoNewline
        Write-Host "              |" -ForegroundColor Gray
    }
    
    Write-Host "───────────────────────────────────────────" -ForegroundColor Gray
}

$warningFired = $false
$overlayForm = $null
$lastConfigWrite = $null
$schedule = $null
$lastScheduleCalcTime = [DateTime]::MinValue

# Run time synchronization asynchronously to prevent blocking the initial boot check
Start-Job -ScriptBlock {
    Set-Service -Name w32time -StartupType Automatic
    Start-Service w32time
    w32tm /config /manualpeerlist:"ntp.ntsc.ac.cn,0x8" /syncfromflags:manual /reliable:YES /update
    w32tm /resync /rediscover
} | Out-Null

# Main monitoring loop: Polling every second, comparing against pre-calculated schedule
while ($true) {
    $now = Get-Date

    # 1. Hot Reload Configuration
    $currentWrite = [DateTime]::MinValue
    if (Test-Path $configPath) {
        $currentWrite = (Get-Item $configPath).LastWriteTime
    }
    $configChanged = ($currentWrite -ne $lastConfigWrite)
    $dayChanged = ($now.Date -ne $lastScheduleCalcTime.Date)

    if ($configChanged -or $dayChanged -or $null -eq $schedule) {
        $config = Get-AppConfiguration
        $lastConfigWrite = $currentWrite
        $schedule = Get-ScheduleState -Now $now -Config $config
        $lastScheduleCalcTime = $now
        $warningFired = $false
    }

    # 2. Check Schedule Boundaries (Need Recalculation?)
    if ($schedule.IsRestricted -and $now -ge $schedule.NextUnlock) {
        $schedule = Get-ScheduleState -Now $now -Config $config
        $lastScheduleCalcTime = $now
        $warningFired = $false
    } elseif (-not $schedule.IsRestricted -and $now -ge $schedule.NextLock) {
        $schedule = Get-ScheduleState -Now $now -Config $config
        $lastScheduleCalcTime = $now
        $warningFired = $false
    }

    # Refresh console status panel
    Show-StatusBoard -IsRestricted $schedule.IsRestricted -Schedule $schedule

    # 3. Action Handlers
    if ($schedule.IsRestricted) {
        # Show fullscreen overlay during rest period
        if ($null -eq $overlayForm) {
            $overlayForm = New-OverlayForm -Opacity 1.0 -HideCursor $true
            $overlayForm.Show()
        }
        $overlayForm.Activate()
        $overlayForm.Topmost = $true 
        # Call system API to lock workstation (like Win + L)
        rundll32.exe user32.dll, LockWorkStation
        Do-WpfEvents
    } 
    else {
        # Close overlay when not in rest period
        if ($null -ne $overlayForm) {
            $overlayForm.Close()
            $overlayForm = $null
        }

        # Show random warning popup if approaching rest time
        if (-not $warningFired -and $schedule.NextWarn -ne [DateTime]::MaxValue -and $now -ge $schedule.NextWarn -and $now -lt $schedule.NextLock) {
            $pick = $config.Warnings | Get-Random
            $warnTimeout = [Math]::Floor(($schedule.NextLock - $now).TotalSeconds)
            if ($warnTimeout -lt 0) { $warnTimeout = 0 }
            Show-WarningMessage -message $pick.Text -buttonText $pick.Button -timeoutSeconds $warnTimeout
            $warningFired = $true
            continue # Immediately re-evaluate loop after window closes
        }
        if ($now -lt $schedule.NextWarn) { $warningFired = $false }
    }

    # Exact 1-second interval sleep for continuous tracking
    Start-Sleep -Seconds 1
}