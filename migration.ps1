# File Migration Script using Robocopy
# This script processes a CSV and copies files/folders including all files inside folders
# from source to destination paths with permission preservation

# Setup logging
$logFolder = "C:\FileMigrationLogs"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "$logFolder\FileMigration_$timestamp.log"

# Create log directory if it doesn't exist
if (-not (Test-Path -Path $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
    Write-Output "Created log directory: $logFolder"
}

# Function to write to log file
function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
       
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
   
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
   
    # Write to log file
    Add-Content -Path $logFile -Value $logEntry
   
    # Also output to console
    switch ($Level) {
        "INFO" { Write-Host $logEntry -ForegroundColor Green }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
    }
}

Write-Log "Starting file migration process"

# Path to your CSV file - update this path
$csvPath = "C:\Path\To\Your\MigrationData.csv"

# Check if CSV file exists
if (-not (Test-Path -Path $csvPath)) {
    Write-Log "CSV file not found at path: $csvPath" -Level "ERROR"
    exit 1
}

Write-Log "Reading CSV file from: $csvPath"

try {
    # Read CSV file
    $migrationData = Import-Csv -Path $csvPath
    Write-Log "Successfully loaded CSV with $($migrationData.Count) records"
}
catch {
    Write-Log "Failed to read CSV file: $_" -Level "ERROR"
    exit 1
}

# Process each row in the CSV
$rowCounter = 0
$successCounter = 0
$errorCounter = 0

foreach ($row in $migrationData) {
    $rowCounter++
   
    # Extract necessary information from the row
    $sourcePath = $row.'Source Path'
    $destinationSubFolder = $row.'Destination Sub Folder'
   
    # Add C:\Users in front of both paths
    $fullSourcePath = "C:\Users" + $sourcePath
    $fullDestinationPath = "C:\Users" + $destinationSubFolder
   
    Write-Log "==== Processing row $rowCounter of $($migrationData.Count) ===="
    Write-Log "Source: $fullSourcePath"
    Write-Log "Destination: $fullDestinationPath"
   
    # Check if source exists
    if (-not (Test-Path -Path $fullSourcePath)) {
        Write-Log "Source does not exist: $fullSourcePath" -Level "ERROR"
        $errorCounter++
        continue
    }
   
    # Determine if source is a file or directory
    $sourceItem = Get-Item -Path $fullSourcePath
   
    if ($sourceItem.PSIsContainer) {
        # It's a directory
        Write-Log "Source is a directory"
       
        # Make sure the destination parent directory exists
        $destinationParent = Split-Path -Path $fullDestinationPath -Parent
        if (-not (Test-Path -Path $destinationParent)) {
            try {
                New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
                Write-Log "Created parent destination directory: $destinationParent"
            }
            catch {
                Write-Log "Failed to create parent destination directory: $_" -Level "ERROR"
                $errorCounter++
                continue
            }
        }
       
        # Use robocopy with specific options for directories - REVISED VERSION
        try {
            $robocopyLogFile = "$logFolder\robocopy_dir_$rowCounter.log"
           
            # IMPORTANT FIX: Ensure destination directory exists first
            if (-not (Test-Path -Path $fullDestinationPath)) {
                New-Item -ItemType Directory -Path $fullDestinationPath -Force | Out-Null
                Write-Log "Created destination directory: $fullDestinationPath"
            }
           
            Write-Log "Executing robocopy to copy directory and all contents..."
           
            # Build robocopy arguments - REVISED FOR RELIABILITY
            # Use /E instead of /MIR to avoid deletion and prevent permission issues
            $robocopyArgs = @(
                "`"$fullSourcePath`"",          # Source with quotes
                "`"$fullDestinationPath`"",     # Destination with quotes
                "/E",                           # Copy subdirectories, including empty ones
                "/COPY:DATSOU",                 # Copy data, attributes, timestamps, security, owner, auditing info
                "/DCOPY:DAT",                   # Copy directory attributes and timestamps
                "/XO",                          # Exclude existing files if destination is newer
                "/R:1",                         # Retry once only (reduced from 3)
                "/W:1",                         # Wait 1 second between retries (reduced from 5)
                "/MT:8",                        # Use 8 threads (reduced from 16 for stability)
                "/NFL",                         # No file listing
                "/NDL",                         # No directory listing
                "/NP",                          # No progress
                "/NC",                          # No class
                "/NS",                          # No size
                "/LOG+:$robocopyLogFile"        # Log file
            )
           
            # Execute robocopy with error handling
            $process = Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs -NoNewWindow -PassThru -Wait
            $exitCode = $process.ExitCode
           
            # Check robocopy exit code and interpret it
            # Robocopy exit codes: 0=No errors, 1=Copied files, 2=Extra files, 4=Mismatched files, 8=Failed copies, 16=Fatal error
            if ($exitCode -lt 8) {
                Write-Log "Directory copy operation completed with exit code $exitCode (Success)"
                $successCounter++
            }
            elseif ($exitCode -eq 16) {
                Write-Log "Directory copy fatal error with exit code 16. Trying alternative approach..." -Level "WARNING"
               
                # Try an alternative approach: copy files directly using Copy-Item
                Write-Log "Attempting alternative copy with Copy-Item cmdlet..."
                Copy-Item -Path "$fullSourcePath\*" -Destination $fullDestinationPath -Recurse -Force -ErrorAction SilentlyContinue
               
                if ($?) {
                    Write-Log "Alternative copy completed successfully"
                    $successCounter++
                }
                else {
                    Write-Log "Alternative copy also failed" -Level "ERROR"
                    $errorCounter++
                }
            }
            else {
                Write-Log "Directory copy encountered issues with exit code $exitCode" -Level "WARNING"
                $errorCounter++
            }
           
            # Log the robocopy output if there were issues
            if ($exitCode -ge 8) {
                if (Test-Path -Path $robocopyLogFile) {
                    $logContent = Get-Content -Path $robocopyLogFile -TotalCount 20
                    Write-Log "Robocopy log snippet (first 20 lines):"
                    foreach ($line in $logContent) {
                        Write-Log "  $line"
                    }
                }
            }
        }
        catch {
            Write-Log "Failed to execute robocopy for directory: $_" -Level "ERROR"
            $errorCounter++
        }
    }
    else {
        # It's a file
        Write-Log "Source is a file"
       
        # Get source directory and filename
        $sourceDirectory = Split-Path -Path $fullSourcePath -Parent
        $fileName = Split-Path -Path $fullSourcePath -Leaf
       
        # Get destination directory and ensure it exists
        $destinationDirectory = Split-Path -Path $fullDestinationPath -Parent
       
        if (-not (Test-Path -Path $destinationDirectory)) {
            try {
                New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
                Write-Log "Created destination directory: $destinationDirectory"
            }
            catch {
                Write-Log "Failed to create destination directory: $_" -Level "ERROR"
                $errorCounter++
                continue
            }
        }
       
        # Use robocopy to copy the file with permissions
        try {
            $robocopyLogFile = "$logFolder\robocopy_file_$rowCounter.log"
           
            Write-Log "Executing robocopy to copy single file..."
           
            # Build robocopy arguments
            $robocopyArgs = @(
                "`"$sourceDirectory`"",         # Source directory with quotes
                "`"$destinationDirectory`"",    # Destination directory with quotes
                "`"$fileName`"",                # File name with quotes
                "/COPY:DATSOU",                 # Copy data, attributes, timestamps, security info, owner info, auditing info
                "/R:1",                         # Retry once
                "/W:1",                         # Wait 1 second between retries
                "/NFL",                         # No file listing
                "/NDL",                         # No directory listing
                "/NP",                          # No progress
                "/LOG+:$robocopyLogFile"        # Log file
            )
           
            # Execute robocopy
            $process = Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs -NoNewWindow -PassThru -Wait
            $exitCode = $process.ExitCode
           
            # Check robocopy exit code
            if ($exitCode -lt 8) {
                Write-Log "File copy completed successfully with exit code $exitCode"
                $successCounter++
            }
            else {
                Write-Log "File copy encountered issues with exit code $exitCode. Trying alternative approach..." -Level "WARNING"
               
                # Try alternative copy with Copy-Item as backup
                Write-Log "Attempting alternative file copy with Copy-Item cmdlet..."
                Copy-Item -Path $fullSourcePath -Destination $fullDestinationPath -Force -ErrorAction SilentlyContinue
               
                if ($?) {
                    Write-Log "Alternative file copy completed successfully"
                    $successCounter++
                }
                else {
                    Write-Log "Alternative file copy also failed" -Level "ERROR"
                    $errorCounter++
                }
            }
        }
        catch {
            Write-Log "Failed to execute robocopy for file: $_" -Level "ERROR"
            $errorCounter++
        }
    }
   
    # Add a separator in the log
    Write-Log "--------------------------------------------------------"
}

# Add a summary section to the log
Write-Log "==================================================="
Write-Log "Migration process completed."
Write-Log "Total rows processed: $rowCounter"
Write-Log "Successful operations: $successCounter"
Write-Log "Operations with errors: $errorCounter"
Write-Log "Full logs available at: $logFile"
Write-Log "Individual robocopy logs available in: $logFolder"
Write-Log "==================================================="

# Output summary to console as well
Write-Host "`nMigration Summary:" -ForegroundColor Cyan
Write-Host "Total processed: $rowCounter" -ForegroundColor White
Write-Host "Successful: $successCounter" -ForegroundColor Green
Write-Host "Errors: $errorCounter" -ForegroundColor $(if ($errorCounter -gt 0) {"Red"} else {"Green"})
Write-Host "Log file: $logFile" -ForegroundColor White