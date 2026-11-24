#Requires -Version 7.4

[CmdletBinding(DefaultParameterSetName = 'Backup')]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $Archive,

    [Parameter(Mandatory, ParameterSetName = 'Restore')]
    [ValidatePattern('^[A-Za-z_][A-Za-z0-9_]*$')]
    [string] $RestoreDatabase
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if ([string]::IsNullOrWhiteSpace($env:PGDATABASE)) {
    throw 'Set PGDATABASE to the name of your source database.'
}

$gpg = (Get-Command gpg.exe -CommandType Application).Source
$zstd = (Get-Command zstd.exe -CommandType Application).Source
$archivePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Archive)

if ($PSCmdlet.ParameterSetName -eq 'Restore') {
    if ($RestoreDatabase -ieq $env:PGDATABASE) {
        throw 'Choose a separate restore database.'
    }

    $psql = (Get-Command psql.exe -CommandType Application).Source
    $tempDir = [System.IO.Directory]::CreateTempSubdirectory('fortune-pies-')
    $compressed = Join-Path $tempDir.FullName 'restore.sql.zst'
    try {
        # Verify the encrypted and compressed streams before executing any SQL.
        & $gpg --batch --output $compressed --decrypt $archivePath
        & $zstd --quiet --test -- $compressed
        & $zstd --quiet --decompress --stdout -- $compressed |
            & $psql -X --no-password --set ON_ERROR_STOP=on --single-transaction --file=- --dbname $RestoreDatabase
    } finally {
        if ([System.IO.File]::Exists($compressed)) {
            [System.IO.File]::Delete($compressed)
        }
        $tempDir.Delete()
    }
    return
}

if ([string]::IsNullOrWhiteSpace($env:GPG_RECIPIENT)) {
    throw 'Set GPG_RECIPIENT to your encryption key fingerprint.'
}
if (Test-Path -LiteralPath $archivePath) {
    throw "Backup already exists: $archivePath"
}

$pgDump = (Get-Command pg_dump.exe -CommandType Application).Source
$null = [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($archivePath))
$partial = "$archivePath.$([guid]::NewGuid().ToString('N')).tmp"
try {
    & $pgDump --no-password --format=plain --no-owner --no-privileges |
        & $zstd --quiet -T0 -3 |
        & $gpg --batch --compress-algo none --encrypt --recipient $env:GPG_RECIPIENT --output $partial

    [System.IO.File]::Move($partial, $archivePath)
    Write-Output "Saved encrypted backup: $archivePath"
} finally {
    if ([System.IO.File]::Exists($partial)) {
        [System.IO.File]::Delete($partial)
    }
}
