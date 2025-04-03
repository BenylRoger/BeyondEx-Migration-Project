# Define Excel file path
$CsvFilePath = "C:\MigrationData.csv"  # Update this
$LogFile = "C:\MigrationLog.txt"

# Ensure logging file exists
if (!(Test-Path $LogFile)) {
    New-Item -ItemType File -Path $LogFile -Force | Out-Null
}

# Function to log messages
function LogMessage {
    param ([string]$Message)
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$TimeStamp - $Message" | Out-File -Append -FilePath $LogFile
}

# Start logging
LogMessage "Migration started."

# Read Excel file
if (!(Test-Path $CsvFilePath)) {
    LogMessage "ERROR: Excel file not found at $CsvFilePath. Exiting."
    exit
}

$Data = Import-Csv -Path $CsvFilePath

# Function to copy files and retain permissions
function Copy-FilesWithPermissions {
    param (
        [string]$Source,
        [string]$Destination
    )
   
    # Get items in source folder
    $Items = Get-ChildItem -Path $Source -Recurse -Force
   
    foreach ($Item in $Items) {
        $TargetPath = $Item.FullName -replace [regex]::Escape($Source), $Destination
       
        if ($Item.PSIsContainer) {
            # Create folders
            if (!(Test-Path $TargetPath)) {
                New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
                LogMessage "Created folder: $TargetPath"
            }
        } else {
            # Copy files
            try {
                Copy-Item -Path $Item.FullName -Destination $TargetPath -Force
                LogMessage "Copied file: $Item.FullName to $TargetPath"
            } catch {
                LogMessage "ERROR: Failed to copy $($Item.FullName) - $_"
            }
        }
       
        # Copy NTFS permissions
        try {
            $Acl = Get-Acl -Path $Item.FullName
            Set-Acl -Path $TargetPath -AclObject $Acl
            LogMessage "Applied permissions to: $TargetPath"
        } catch {
            LogMessage "ERROR: Failed to set permissions on $TargetPath - $_"
        }
    }
}

# Process each row in the Excel file
foreach ($Row in $Data) {
    $SourcePath = "C:\" + $Row."Source Path"
    $DestinationPath = "C:\" + $Row."Destination Sub Folder"
   
    # Check if source exists
    if (!(Test-Path $SourcePath)) {
        LogMessage "ERROR: Source path does not exist: $SourcePath. Skipping."
        continue
    }
   
    # Create destination folder if it doesn't exist
    if (!(Test-Path $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        LogMessage "Created destination folder: $DestinationPath"
    }
   
    # Start migration for this entry
    Copy-FilesWithPermissions -Source $SourcePath -Destination $DestinationPath
}

# Final logging
LogMessage "Migration completed successfully."