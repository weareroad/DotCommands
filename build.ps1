param(
    [ValidateSet("all", "cdn", "lsn", "setnn", "set32", "set64", "set85")]
    [string] $Command = "all",

    [string] $Assembler = "sjasmplus",

    [string] $Z88dkRoot = "",

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
        Name = "lsn"
        Source = "src/lsn"
        Output = "dot/lsn"
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

function Find-Z88dkTool([string] $Name) {
    if ($Z88dkRoot) {
        $candidate = Join-Path (Join-Path $Z88dkRoot "bin") "$Name.exe"
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Cannot find $Name at $candidate"
        }
        return $candidate
    }

    $commandInfo = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $commandInfo) {
        throw "Cannot find $Name on PATH; pass -Z88dkRoot with the z88dk installation directory"
    }
    return $commandInfo.Source
}

function Build-Lsn($Definition) {
    $sourceDirectory = Join-Path $PSScriptRoot $Definition.Source
    $output = Join-Path $PSScriptRoot $Definition.Output
    $stageDirectory = Join-Path $PSScriptRoot ".tools/build/lsn"
    $stageParent = Split-Path -Parent $stageDirectory

    $zcc = Find-Z88dkTool "zcc"
    $zx7 = Find-Z88dkTool "z88dk-zx7"

    Remove-Item -LiteralPath $output -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stageDirectory -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null

    try {
        Copy-Item -Path (Join-Path $sourceDirectory "*") -Destination $stageDirectory -Recurse

        Push-Location $stageDirectory
        try {
            & $zx7 -f "ls-help.txt"
            if ($LASTEXITCODE -ne 0) {
                throw "z88dk-zx7 failed for lsn with exit code $LASTEXITCODE"
            }

            $compilerArguments = @(
                "+zxn",
                "-startup=30",
                "-clib=sdcc_iy",
                "-SO3",
                "--max-allocs-per-node200000",
                "--opt-code-size",
                "@zproject.lst",
                "-o", "lsn",
                "-pragma-include:zpragma.inc",
                "-subtype=dotn",
                '-Cz"--clean"',
                "-create-app"
            )

            & $zcc @compilerArguments
            if ($LASTEXITCODE -ne 0) {
                throw "zcc failed for lsn with exit code $LASTEXITCODE"
            }
        }
        finally {
            Pop-Location
        }

        $builtImage = Join-Path $stageDirectory "LSN"
        if (-not (Test-Path -LiteralPath $builtImage -PathType Leaf)) {
            throw "zcc did not produce the expected LSN dotN image"
        }

        $outputDirectory = Split-Path -Parent $output
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
        Copy-Item -LiteralPath $builtImage -Destination $output

        $size = (Get-Item -LiteralPath $output).Length
        if ($size -eq 0) {
            Remove-Item -LiteralPath $output -ErrorAction SilentlyContinue
            throw "$($Definition.Output) is empty"
        }

        Write-Host "Built $($Definition.Output) ($size bytes, dotN)"
    }
    finally {
        Remove-Item -LiteralPath $stageDirectory -Recurse -Force -ErrorAction SilentlyContinue
        if ((Test-Path -LiteralPath $stageParent -PathType Container) -and
            -not (Get-ChildItem -LiteralPath $stageParent -Force)) {
            Remove-Item -LiteralPath $stageParent -Force
        }
    }
}

$selectedCommands = switch ($Command) {
    "all"   { $commands }
    "setnn" { $commands | Where-Object { $null -ne $_.ReferenceSha256 } }
    default { $commands | Where-Object Name -eq $Command }
}

foreach ($definition in $selectedCommands) {
    if ($definition.Name -eq "lsn") {
        Build-Lsn $definition
        continue
    }

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
