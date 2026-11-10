# ================================================================
# Pendrive_X - ANSI QR code renderer (Windows PowerShell 5.1+)
# ================================================================
# Dependency-free byte-mode QR encoder (ECC M, mask 0). Used by
# start-windows.bat so LAN mode can show a scannable QR in the
# terminal without installing qrencode or Python.
#
# Usage:
#   powershell -NoProfile -File tools\qr.ps1 -Text "http://192.168.1.20:11434"
#   powershell -NoProfile -File tools\qr.ps1 -Text "..." -Raw
# ================================================================
param(
    [Parameter(Mandatory = $true)][string]$Text,
    [ValidateSet("l", "m")][string]$Ecc = "m",
    [ValidateRange(0, 7)][int]$Mask = 0,
    [switch]$NoUrl,
    [switch]$Raw
)

$ErrorActionPreference = "Stop"

# -----------------------------------------------------------------
# QR constants
# -----------------------------------------------------------------
$ECC_M = [int[]](-1,10,16,26,18,24,16,18,22,22,26,30,22,22,24,24,28,28,26,26,26,26,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28)
$ECC_L = [int[]](-1,7,10,15,20,26,18,20,24,30,18,20,24,26,30,22,24,28,30,28,28,28,28,30,30,26,28,30,30,30,30,30,30,30,30,30,30,30,30,30)
$BLOCKS_M = [int[]](-1,1,1,1,2,2,4,4,4,5,5,5,8,9,9,10,10,11,13,14,16,17,17,18,20,21,23,25,26,28,29,31,33,35,37,38,40,43,45,47,49)
$BLOCKS_L = [int[]](-1,1,1,1,1,1,2,2,2,2,4,4,4,4,4,6,6,6,6,7,8,8,9,9,10,12,12,12,13,14,15,16,17,18,19,19,20,21,22,24,25)
$ALIGN = @{
    1 = @(); 2 = @(6,18); 3 = @(6,22); 4 = @(6,26); 5 = @(6,30); 6 = @(6,34)
    7 = @(6,22,38); 8 = @(6,24,42); 9 = @(6,26,46); 10 = @(6,28,50)
    11 = @(6,30,54); 12 = @(6,32,58); 13 = @(6,34,62); 14 = @(6,26,46,66)
    15 = @(6,26,48,70); 16 = @(6,26,50,74); 17 = @(6,30,54,78)
    18 = @(6,30,56,82); 19 = @(6,30,58,86); 20 = @(6,34,62,90)
}

# -----------------------------------------------------------------
# GF(256) / Reed-Solomon
# -----------------------------------------------------------------
$script:GfExp = New-Object int[] 512
$script:GfLog = New-Object int[] 256
$gfX = 1
for ($i = 0; $i -lt 255; $i++) {
    $script:GfExp[$i] = $gfX
    $script:GfLog[$gfX] = $i
    $gfX = $gfX -shl 1
    if ($gfX -band 0x100) { $gfX = $gfX -bxor 0x11D }
}
for ($i = 255; $i -lt 512; $i++) { $script:GfExp[$i] = $script:GfExp[$i - 255] }

function Get-GfMul([int]$X, [int]$Y) {
    if ($X -eq 0 -or $Y -eq 0) { return 0 }
    return $script:GfExp[$script:GfLog[$X] + $script:GfLog[$Y]]
}

function Get-RsDivisor([int]$Degree) {
    $result = New-Object int[] $Degree
    $result[$Degree - 1] = 1
    $root = 1
    for ($i = 0; $i -lt $Degree; $i++) {
        for ($j = 0; $j -lt $Degree; $j++) {
            $result[$j] = Get-GfMul $result[$j] $root
            if ($j + 1 -lt $Degree) { $result[$j] = $result[$j] -bxor $result[$j + 1] }
        }
        $root = Get-GfMul $root 2
    }
    return ,$result
}

function Get-RsRemainder([int[]]$Data, [int[]]$Divisor) {
    $result = New-Object int[] $Divisor.Length
    foreach ($b in $Data) {
        $factor = $b -bxor $result[0]
        for ($i = 0; $i -lt $result.Length - 1; $i++) { $result[$i] = $result[$i + 1] }
        $result[$result.Length - 1] = 0
        for ($i = 0; $i -lt $Divisor.Length; $i++) {
            $result[$i] = $result[$i] -bxor (Get-GfMul $Divisor[$i] $factor)
        }
    }
    return ,$result
}

function Add-Bits([System.Collections.Generic.List[int]]$Out, [int]$Value, [int]$Length) {
    for ($i = $Length - 1; $i -ge 0; $i--) {
        $Out.Add((($Value -shr $i) -band 1))
    }
}

function Get-RawDataModules([int]$Version) {
    $result = (16 * $Version + 128) * $Version + 64
    if ($Version -ge 2) {
        $numAlign = [math]::Floor($Version / 7) + 2
        $result -= (25 * $numAlign - 10) * $numAlign - 55
        if ($Version -ge 7) { $result -= 36 }
    }
    return $result
}

function Get-DataCodewordCount([int]$Version, [string]$EccLevel) {
    if ($EccLevel -eq "l") {
        return ([math]::Floor((Get-RawDataModules $Version) / 8) - $ECC_L[$Version] * $BLOCKS_L[$Version])
    }
    return ([math]::Floor((Get-RawDataModules $Version) / 8) - $ECC_M[$Version] * $BLOCKS_M[$Version])
}

function New-Codewords([byte[]]$Data, [int]$Version, [string]$EccLevel) {
    $capacityBits = (Get-DataCodewordCount $Version $EccLevel) * 8
    $bits = New-Object 'System.Collections.Generic.List[int]'
    Add-Bits $bits 0x4 4
    $countBits = 8
    if ($Version -gt 9) { $countBits = 16 }
    Add-Bits $bits $Data.Length $countBits
    foreach ($b in $Data) { Add-Bits $bits $b 8 }
    if ($bits.Count -gt $capacityBits) { throw "data too long for QR version $Version" }
    Add-Bits $bits 0 ([math]::Min(4, $capacityBits - $bits.Count))
    $padBits = 0
    while ((($bits.Count + $padBits) % 8) -ne 0) { $padBits++ }
    Add-Bits $bits 0 $padBits
    $pad = 0xEC
    while ($bits.Count -lt $capacityBits) {
        Add-Bits $bits $pad 8
        $pad = $pad -bxor 0xFD
    }

    $dataCodewords = New-Object int[] ($bits.Count / 8)
    for ($i = 0; $i -lt $bits.Count; $i++) {
        $dataCodewords[[math]::Floor($i / 8)] = $dataCodewords[[math]::Floor($i / 8)] -bor ($bits[$i] -shl (7 - ($i % 8)))
    }

    if ($EccLevel -eq "l") {
        $eccLen = $ECC_L[$Version]; $numBlocks = $BLOCKS_L[$Version]
    } else {
        $eccLen = $ECC_M[$Version]; $numBlocks = $BLOCKS_M[$Version]
    }
    $rawCodewords = [math]::Floor((Get-RawDataModules $Version) / 8)
    $numShortBlocks = $numBlocks - ($rawCodewords % $numBlocks)
    $shortBlockLen = [math]::Floor($rawCodewords / $numBlocks)
    $divisor = Get-RsDivisor $eccLen

    $blocks = @()
    $k = 0
    for ($i = 0; $i -lt $numBlocks; $i++) {
        $datLen = $shortBlockLen - $eccLen
        if ($i -ge $numShortBlocks) { $datLen++ }
        $dat = New-Object 'System.Collections.Generic.List[int]'
        for ($j = 0; $j -lt $datLen; $j++) { $dat.Add($dataCodewords[$k]); $k++ }
        $eccBytes = Get-RsRemainder $dat.ToArray() $divisor
        if ($i -lt $numShortBlocks) { $dat.Add(0) }
        $block = New-Object 'System.Collections.Generic.List[int]'
        foreach ($d in $dat) { $block.Add($d) }
        foreach ($e in $eccBytes) { $block.Add($e) }
        $blocks += ,$block.ToArray()
    }

    $result = New-Object 'System.Collections.Generic.List[int]'
    $blockLen = $blocks[0].Length
    for ($i = 0; $i -lt $blockLen; $i++) {
        for ($j = 0; $j -lt $numBlocks; $j++) {
            if (($i -ne ($shortBlockLen - $eccLen)) -or ($j -ge $numShortBlocks)) {
                $result.Add($blocks[$j][$i])
            }
        }
    }
    return ,$result.ToArray()
}

# -----------------------------------------------------------------
# Matrix construction
# -----------------------------------------------------------------
function New-QrObject([int]$Version) {
    $size = $Version * 4 + 17
    return @{
        Version = $Version
        Size    = $size
        Modules = New-Object 'bool[,]' $size, $size
        Func    = New-Object 'bool[,]' $size, $size
    }
}

function Set-QrFunction($Qr, [int]$X, [int]$Y, [bool]$Dark) {
    $Qr.Modules[$Y, $X] = $Dark
    $Qr.Func[$Y, $X] = $true
}

function Initialize-FunctionPatterns($Qr) {
    $size = $Qr.Size
    for ($i = 0; $i -lt $size; $i++) {
        Set-QrFunction $Qr 6 $i (($i % 2) -eq 0)
        Set-QrFunction $Qr $i 6 (($i % 2) -eq 0)
    }
    foreach ($corner in @(@(3,3), @(($size - 4),3), @(3,($size - 4)))) {
        $cx = $corner[0]; $cy = $corner[1]
        for ($dy = -4; $dy -le 4; $dy++) {
            for ($dx = -4; $dx -le 4; $dx++) {
                $x = $cx + $dx; $y = $cy + $dy
                if ($x -ge 0 -and $x -lt $size -and $y -ge 0 -and $y -lt $size) {
                    $dist = [math]::Max([math]::Abs($dx), [math]::Abs($dy))
                    Set-QrFunction $Qr $x $y (($dist -ne 2) -and ($dist -ne 4))
                }
            }
        }
    }
    $positions = $ALIGN[$Qr.Version]
    foreach ($ay in $positions) {
        foreach ($ax in $positions) {
            if (($ax -eq 6 -and $ay -eq 6) -or ($ax -eq 6 -and $ay -eq ($size - 7)) -or ($ax -eq ($size - 7) -and $ay -eq 6)) { continue }
            for ($dy = -2; $dy -le 2; $dy++) {
                for ($dx = -2; $dx -le 2; $dx++) {
                    $dist = [math]::Max([math]::Abs($dx), [math]::Abs($dy))
                    Set-QrFunction $Qr ($ax + $dx) ($ay + $dy) ($dist -ne 1)
                }
            }
        }
    }
    # Reserve format information (timing modules at (8,6)/(6,8) stay untouched)
    foreach ($i in @(0,1,2,3,4,5,7,8)) {
        Set-QrFunction $Qr 8 $i $false
        Set-QrFunction $Qr $i 8 $false
    }
    for ($i = 0; $i -lt 8; $i++) {
        Set-QrFunction $Qr ($size - 1 - $i) 8 $false
        Set-QrFunction $Qr 8 ($size - 1 - $i) $false
    }
    Set-QrFunction $Qr 8 ($size - 8) $true
    if ($Qr.Version -ge 7) {
        for ($i = 0; $i -lt 18; $i++) {
            $a = $size - 11 + ($i % 3); $b = [math]::Floor($i / 3)
            Set-QrFunction $Qr $a $b $false
            Set-QrFunction $Qr $b $a $false
        }
    }
}

function Set-FormatBits($Qr, [int]$EccFormatBits, [int]$MaskPattern) {
    $data = ($EccFormatBits -shl 3) -bor $MaskPattern
    $rem = $data
    for ($i = 0; $i -lt 10; $i++) { $rem = ($rem -shl 1) -bxor ((($rem -shr 9) -band 1) * 0x537) }
    $bits = (($data -shl 10) -bor $rem) -bxor 0x5412
    $bit = { param($n) (($bits -shr $n) -band 1) -ne 0 }
    for ($i = 0; $i -lt 6; $i++) { Set-QrFunction $Qr 8 $i (& $bit $i) }
    Set-QrFunction $Qr 8 7 (& $bit 6)
    Set-QrFunction $Qr 8 8 (& $bit 7)
    Set-QrFunction $Qr 7 8 (& $bit 8)
    for ($i = 9; $i -lt 15; $i++) { Set-QrFunction $Qr (14 - $i) 8 (& $bit $i) }
    for ($i = 0; $i -lt 8; $i++) { Set-QrFunction $Qr ($Qr.Size - 1 - $i) 8 (& $bit $i) }
    for ($i = 8; $i -lt 15; $i++) { Set-QrFunction $Qr 8 ($Qr.Size - 15 + $i) (& $bit $i) }
    Set-QrFunction $Qr 8 ($Qr.Size - 8) $true
}

function Set-VersionBits($Qr) {
    if ($Qr.Version -lt 7) { return }
    $rem = $Qr.Version
    for ($i = 0; $i -lt 12; $i++) { $rem = ($rem -shl 1) -bxor ((($rem -shr 11) -band 1) * 0x1F25) }
    $bits = ($Qr.Version -shl 12) -bor $rem
    for ($i = 0; $i -lt 18; $i++) {
        $dark = (($bits -shr $i) -band 1) -ne 0
        $a = $Qr.Size - 11 + ($i % 3); $b = [math]::Floor($i / 3)
        Set-QrFunction $Qr $a $b $dark
        Set-QrFunction $Qr $b $a $dark
    }
}

function Set-DataCodewords($Qr, [int[]]$Codewords) {
    $bits = New-Object 'System.Collections.Generic.List[int]'
    foreach ($cw in $Codewords) { Add-Bits $bits $cw 8 }
    $i = 0
    $right = $Qr.Size - 1
    while ($right -ge 1) {
        if ($right -le 6) { $right-- }
        for ($vert = 0; $vert -lt $Qr.Size; $vert++) {
            for ($j = 0; $j -lt 2; $j++) {
                $x = $right - $j
                $upward = (((($right + 1) -band 2)) -eq 0)
                if ($upward) { $y = $Qr.Size - 1 - $vert } else { $y = $vert }
                if ((-not $Qr.Func[$y, $x]) -and ($i -lt $bits.Count)) {
                    $Qr.Modules[$y, $x] = ($bits[$i] -ne 0)
                    $i++
                }
            }
        }
        $right -= 2
    }
}

function Invoke-Mask($Qr, [int]$MaskPattern) {
    for ($y = 0; $y -lt $Qr.Size; $y++) {
        for ($x = 0; $x -lt $Qr.Size; $x++) {
            if ($Qr.Func[$y, $x]) { continue }
            $invert = $false
            switch ($MaskPattern) {
                0 { $invert = (($x + $y) % 2) -eq 0 }
                1 { $invert = ($y % 2) -eq 0 }
                2 { $invert = ($x % 3) -eq 0 }
                3 { $invert = (($x + $y) % 3) -eq 0 }
                4 { $invert = (([math]::Floor($x / 3) + [math]::Floor($y / 2)) % 2) -eq 0 }
                5 { $invert = ((($x * $y) % 2) + (($x * $y) % 3)) -eq 0 }
                6 { $invert = (((($x * $y) % 2) + (($x * $y) % 3)) % 2) -eq 0 }
                7 { $invert = (((($x + $y) % 2) + (($x * $y) % 3)) % 2) -eq 0 }
            }
            if ($invert) { $Qr.Modules[$y, $x] = -not $Qr.Modules[$y, $x] }
        }
    }
}

function New-QrCode([string]$Value, [string]$EccLevel, [int]$MaskPattern) {
    $data = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $chosenVersion = 0
    $chosenCodewords = $null
    for ($v = 1; $v -le 20; $v++) {
        try {
            $cw = New-Codewords $data $v $EccLevel
            $chosenVersion = $v
            $chosenCodewords = $cw
            break
        } catch { if ($env:PX_QR_DEBUG) { Write-Host ("v{0}: {1}" -f $v, $_.Exception.Message) } }
    }
    if ($chosenVersion -eq 0) { throw "data too long for QR versions 1-20" }
    $qr = New-QrObject $chosenVersion
    Initialize-FunctionPatterns $qr
    $eccFormat = if ($EccLevel -eq "m") { 0 } else { 1 }
    Set-FormatBits $qr $eccFormat $MaskPattern
    Set-VersionBits $qr
    Set-DataCodewords $qr $chosenCodewords
    Invoke-Mask $qr $MaskPattern
    return $qr
}

# -----------------------------------------------------------------
# Output
# -----------------------------------------------------------------
function Enable-AnsiOutput {
    try {
        Add-Type -Namespace PendriveNative -Name ConsoleMode -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@ -ErrorAction Stop
        $handle = [PendriveNative.ConsoleMode]::GetStdHandle(-11)
        $mode = 0
        if ([PendriveNative.ConsoleMode]::GetConsoleMode($handle, [ref]$mode)) {
            [void][PendriveNative.ConsoleMode]::SetConsoleMode($handle, ($mode -bor 0x0004))
        }
    } catch { }
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
}

function Write-RawQr($Qr) {
    for ($y = 0; $y -lt $Qr.Size; $y++) {
        $sb = New-Object System.Text.StringBuilder
        for ($x = 0; $x -lt $Qr.Size; $x++) {
            [void]$sb.Append($(if ($Qr.Modules[$y, $x]) { "#" } else { "." }))
        }
        Write-Output $sb.ToString()
    }
}

function Write-AnsiQr($Qr, [int]$QuietZone = 4) {
    $esc = [char]27
    $bb = "$esc[38;5;0m$esc[48;5;0m"
    $bw = "$esc[38;5;0m$esc[48;5;15m"
    $wb = "$esc[38;5;15m$esc[48;5;0m"
    $ww = "$esc[38;5;15m$esc[48;5;15m"
    $reset = "$esc[0m"
    $total = $Qr.Size + $QuietZone * 2
    for ($y = 0; $y -lt $total; $y += 2) {
        $sb = New-Object System.Text.StringBuilder
        for ($x = 0; $x -lt $total; $x++) {
            $mx = $x - $QuietZone; $my = $y - $QuietZone
            $top = ($mx -ge 0 -and $mx -lt $Qr.Size -and $my -ge 0 -and $my -lt $Qr.Size -and $Qr.Modules[$my, $mx])
            $my2 = $y + 1 - $QuietZone
            $bottom = ($mx -ge 0 -and $mx -lt $Qr.Size -and $my2 -ge 0 -and $my2 -lt $Qr.Size -and $Qr.Modules[$my2, $mx])
            if ($top -and $bottom) { [void]$sb.Append($bb) }
            elseif ($top) { [void]$sb.Append($bw) }
            elseif ($bottom) { [void]$sb.Append($wb) }
            else { [void]$sb.Append($ww) }
            [void]$sb.Append([char]0x2580)
        }
        [void]$sb.Append($reset)
        Write-Output $sb.ToString()
    }
}

if ($Raw) {
    $qr = New-QrCode $Text $Ecc $Mask
    Write-RawQr $qr
    exit 0
}

Enable-AnsiOutput
$qr = New-QrCode $Text $Ecc $Mask
Write-AnsiQr $qr
if (-not $NoUrl) {
    Write-Output ""
    Write-Output ("  " + $Text)
}
