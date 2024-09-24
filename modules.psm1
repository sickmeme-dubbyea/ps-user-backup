 # SystemBackup.psm1

# Global variable for bookmark paths
$global:BookmarkPaths = @{
    Chrome  = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Bookmarks"
    Edge    = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Bookmarks"
    Firefox  = "$env:APPDATA\Mozilla\Firefox\Profiles"
}

# Global array for browsers
$global:Browsers = @("chrome", "msedge", "firefox")

function Stop-Browsers {
    param (
        [string[]]$browsers = $global:Browsers
    )

    foreach ($browser in $browsers) {
        $processes = Get-Process -Name $browser -ErrorAction SilentlyContinue
        if ($processes) {
            Stop-Process -Name $browser -Force
            Write-Host "$browser terminated."
        } else {
            Write-Host "$browser is not running."
        }
    }
}

function Manage-OutputDir {
    param (
        [string]$directory
    )

    if (-not (Test-Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $directory"
    }
}

function Get-DriveMappings {
    param (
        [string]$outputDir = "$env:USERPROFILE\OneDrive\_backups\DriveMapping"
    )

    Manage-OutputDir -directory $outputDir

    $mappedDrives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match "\\" -and $_.Root -ne "$env:systemdrive\" }
    $driveMappings = $mappedDrives | Select-Object Name, @{Name='Root'; Expression={$_.DisplayRoot}} | ConvertTo-Json -Depth 3

    $outputFile = Join-Path -Path $outputDir -ChildPath "DriveMappings.json"
    $driveMappings | Set-Content -Path $outputFile -Force
    Write-Host "Drive mappings saved to: $outputFile"
}

function Restore-DriveMappings {
    param (
        [string]$inputDir = "$env:USERPROFILE\OneDrive\_backups\DriveMapping",
        [string]$inputFile = "DriveMappings.json"
    )

    $inputFilePath = Join-Path -Path $inputDir -ChildPath $inputFile
    if (-Not (Test-Path $inputFilePath)) {
        Write-Host "Input file not found: $inputFilePath"
        return
    }

    $driveMappings = Get-Content -Path $inputFilePath | ConvertFrom-Json
    foreach ($mapping in $driveMappings) {
        if (-Not (Get-PSDrive -Name $mapping.Name -ErrorAction SilentlyContinue)) {
            New-PSDrive -Name $mapping.Name -PSProvider FileSystem -Root $mapping.Root -Scope Global -Persist 
            Write-Host "Restored drive mapping: Name=$($mapping.Name), Root=$($mapping.Root)"
        } else {
            Write-Host "Drive mapping already exists: Name=$($mapping.Name)"
        }
    }
}

function Get-Printers {
    param (
        [string]$outputDir = "$env:USERPROFILE\OneDrive\_backups\Printers"
    )

    Manage-OutputDir -directory $outputDir

    $printers = Get-Printer | Select-Object Name, DriverName, PortName, Shared, Location, Comment
    $outputFile = Join-Path -Path $outputDir -ChildPath "Printers.json"
    $printers | ConvertTo-Json -Depth 3 | Set-Content -Path $outputFile -Force
    Write-Host "Printer details saved to: $outputFile"
}

function Restore-Printers {
    param (
        [string]$inputDir = "$env:USERPROFILE\OneDrive\_backups\Printers",
        [string]$inputFile = "Printers.json"
    )

    $inputFilePath = Join-Path -Path $inputDir -ChildPath $inputFile
    if (-Not (Test-Path $inputFilePath)) {
        Write-Host "Input file not found: $inputFilePath"
        return
    }

    $printers = Get-Content -Path $inputFilePath | ConvertFrom-Json
    foreach ($printer in $printers) {
        if (-Not (Get-Printer -Name $printer.Name -ErrorAction SilentlyContinue)) {
            Add-Printer -Name $printer.Name -DriverName $printer.DriverName -PortName $printer.PortName -Shared:$printer.Shared -Location:$printer.Location -Comment:$printer.Comment
            Write-Host "Restored printer: $($printer.Name), Driver=$($printer.DriverName)"
        } else {
            Write-Host "Printer already exists: $($printer.Name)"
        }
    }
}

function Backup-BrowserBookmarks {
    param (
        [string]$backupDir = "$env:USERPROFILE\OneDrive\_backups\Browser"
    )

    Manage-OutputDir -directory $backupDir

    Stop-Browsers

    foreach ($browser in $global:BookmarkPaths.Keys) {
        $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
        $outputFile = Join-Path -Path $backupDir -ChildPath ("Bookmarks-$($browser.ToLower())-$timestamp.json")

        if (Test-Path $global:BookmarkPaths[$browser]) {
            if ($browser -in @("Chrome", "Edge")) {
                Copy-Item -Path $global:BookmarkPaths[$browser] -Destination $outputFile
                Write-Host "$browser bookmarks backed up to: $outputFile"
            } elseif ($browser -eq "Firefox") {
                $profilePath = Get-ChildItem -Path $global:BookmarkPaths[$browser] -Directory | Select-Object -First 1
                if ($profilePath) {
                    Copy-Item -Path (Join-Path $profilePath.FullName "places.sqlite") -Destination $outputFile
                    Write-Host "Firefox bookmarks backed up to: $outputFile."
                } else {
                    Write-Warning "No Firefox profile found."
                }
            }
        } else {
            Write-Warning "$browser bookmarks not found."
        }
    }

    Write-Host "All browser backups completed."
}

function Restore-BrowserBookmarks {
    param (
        [string]$inputDir = "$env:USERPROFILE\OneDrive\_backups\Browser",
        [string]$timestamp = "latest"
    )

    Stop-Browsers

    foreach ($browser in $global:BookmarkPaths.Keys) {
        if ($timestamp -eq "latest") {
            $latestBackup = Get-ChildItem "$inputDir" ("Bookmarks-$($browser)*.json") | Sort-Object LastWriteTime | Select-Object -First 1
            if ($latestBackup) {
                Restore-BookmarkData -browser $browser -sourceFile $latestBackup.FullName
            } else {
                Write-Warning "No backup found for $browser."
            }
        } else {
            $inputFile = Join-Path -Path $inputDir -ChildPath ("Bookmarks-$($browser)-$timestamp.json")
            if (Test-Path $inputFile) {
                Restore-BookmarkData -browser $browser -sourceFile $inputFile
            } else {
                Write-Warning "Backup file not found for $browser at $inputFile."
            }
        }
    }
}

function Restore-BookmarkData {
    param (
        [string]$browser,
        [string]$sourceFile
    )

    switch ($browser.ToLower()) {
        'chrome' {
            Copy-Item -Path $sourceFile -Destination $global:BookmarkPaths[$browser]
            Write-Host "Restored $browser bookmarks from $sourceFile"
        }
        'edge' {
            Copy-Item -Path $sourceFile -Destination $global:BookmarkPaths[$browser]
            Write-Host "Restored $browser bookmarks from $sourceFile"
        }
        'firefox' {
            $profilePath = Get-ChildItem $global:BookmarkPaths[$browser] -Directory | Select-Object -First 1
            if ($profilePath) {
                Copy-Item -Path $sourceFile -Destination (Join-Path $profilePath.FullName 'places.sqlite')
                Write-Host "Restored $browser bookmarks from $sourceFile"
            } else {
                Write-Warning "No Firefox profile found."
            }
        }
        default {
            Write-Warning "Unsupported browser name: $browser"
        }
    }
}

# Export functions for use in other scripts or modules.
Write-Host "`nLoading Backup Module..."
Export-ModuleMember -Function Stop-Browsers, Get-DriveMappings, Restore-DriveMappings, Get-Printers, Restore-Printers, Backup-BrowserBookmarks, Restore-BrowserBookmarks
