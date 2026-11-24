param(
    [ValidateSet("all", "cdn", "setnn", "set32", "set64", "set85")]
    [string] $Command = "all",

    [string] $Assembler = "sjasmplus",

    [switch] $Clean,

    [switch] $VerifySetNNReference
)

$ErrorActionPreference = "Stop"

$commands = @(
    [pscustomobject]@{
        Name = "cdn"
        Source = "src/cdn.asm"
        Output = "dot/cdn"
        ReferenceSha256 = $null
    },
    [pscustomobject]@{
        Name = "set32"
        Source = "src/set32.asm"
        Output = "dot/set32"
        ReferenceSha256 = "917c7975781993682ab896eb6c70624a15aba786a7965a94abceeb5790424445"
    },
    [pscustomobject]@{
        Name = "set64"
        Source = "src/set64.asm"
        Output = "dot/set64"
        ReferenceSha256 = "a877272fa3e64f88e7d5551f20433aa06e2978c7e4f2b0db47dd0ad6f3a81078"
    },
    [pscustomobject]@{
        Name = "set85"
        Source = "src/set85.asm"
        Output = "dot/set85"
        ReferenceSha256 = "ae948fbeb8048a2ae708fc949993e480ac62cb120214ddd5829829badc3aa57a"
    }
)

function Get-Sha256([string] $Path) {
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $hash = $hasher.ComputeHash($stream)
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $hasher.Dispose()
    }

    return ([System.BitConverter]::ToString($hash)).Replace("-", "").ToLowerInvariant()
}

$selectedCommands = switch ($Command) {
    "all"   { $commands }
    "setnn" { $commands | Where-Object Name -ne "cdn" }
    default { $commands | Where-Object Name -eq $Command }
}

foreach ($definition in $selectedCommands) {
    $source = (Join-Path $PSScriptRoot $definition.Source).Replace("\", "/")
    $output = (Join-Path $PSScriptRoot $definition.Output).Replace("\", "/")
    $verifyReference = $VerifySetNNReference -and $null -ne $definition.ReferenceSha256
    $assemblyOutput = if ($verifyReference) { "$output.verify.tmp" } else { $output }

    if ($Clean -and -not $verifyReference) {
        Remove-Item -LiteralPath $output -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $assemblyOutput -ErrorAction SilentlyContinue

    try {
        $assemblerArguments = @("--zxnext", "--nologo", "--cleanonerror")
        if ($verifyReference) {
            $assemblerArguments += "-DREFERENCE_BASELINE"
        }
        $assemblerArguments += "--raw=$assemblyOutput"
        $assemblerArguments += $source

        & $Assembler @assemblerArguments
        if ($LASTEXITCODE -ne 0) {
            throw "SJAsmPlus failed for $($definition.Name) with exit code $LASTEXITCODE"
        }

        $size = (Get-Item -LiteralPath $assemblyOutput).Length
        if ($size -gt 8192) {
            Remove-Item -LiteralPath $assemblyOutput -ErrorAction SilentlyContinue
            throw "$($definition.Output) is $size bytes; a standard dot command may not exceed 8192 bytes"
        }

        if ($verifyReference) {
            $actualHash = Get-Sha256 $assemblyOutput
            if ($actualHash -ne $definition.ReferenceSha256) {
                throw "$($definition.Name) does not match its 37-byte reference binary (SHA-256 $actualHash)"
            }

            Write-Host "Verified $($definition.Output) against its reference SHA-256 ($size bytes)"
        }
        else {
            Write-Host "Built $($definition.Output) ($size bytes)"
        }
    }
    finally {
        if ($verifyReference) {
            Remove-Item -LiteralPath $assemblyOutput -ErrorAction SilentlyContinue
        }
    }
}
