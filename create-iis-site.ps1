# The following code will create an IIS site and it associated Application Pool. 
# Please note that you will be required to run PS with elevated permissions. 
# Visit http://ifrahimblog.wordpress.com/2014/02/26/run-powershell-elevated-permissions-import-iis-module/ 

# set-executionpolicy unrestricted
# https://octopus.com/blog/iis-powershell#retry-retry-retry

clear


$SiteFolderPath = "C:\WebSite11"              # Website Folder
$SiteAppPool = "MyAppPool11"                  # Application Pool Name
$SiteName = "MySite11"                        # IIS Site Name
$SiteHostName = "localhost11"                 # Host Header

function Execute-WithRetry([ScriptBlock] $command) {
    $attemptCount = 0
    $operationIncomplete = $true
    $maxFailures = 10
    $sleepBetweenFailures = 2

    while ($operationIncomplete -and $attemptCount -lt $maxFailures) {
        $attemptCount = ($attemptCount + 1)

        if ($attemptCount -ge 2) {
            Write-Host "Waiting for $sleepBetweenFailures seconds before retrying..."
            Start-Sleep -s $sleepBetweenFailures
            Write-Host "Retrying..."
        }

        try {
            # Call the script block
            & $command

            $operationIncomplete = $false
        } catch [System.Exception] {
            if ($attemptCount -lt ($maxFailures)) {
                Write-Host ("Attempt $attemptCount of $maxFailures failed: " + $_.Exception.Message)
            } else {
                throw
            }
        }
    }
}


Reset-IISServerManager -Confirm:$false

Write-Host "Loading modules"

Import-Module IISAdministration -ErrorAction SilentlyContinue

# We use this folder for testing, often as the physical directory for sites


$ErrorActionPreference = "Continue"

# In case previous invocations left one open
Stop-IISCommitDelay -commit $false -WarningAction SilentlyContinue
Stop-IISCommitDelay -commit $false -WarningAction SilentlyContinue



#$manager = Get-IISServerManager

# The pattern here is to get the things you want, then check if they are null
 mkdir "C:\Sites" -ErrorAction SilentlyContinue
 mkdir $SiteFolderPath -ErrorAction SilentlyContinue
$manager = Get-IISServerManager

if ($manager.ApplicationPools[$SiteAppPool] -eq $null) {
    # Application pool does not exist, create it...
    # ...
 Execute-WithRetry { 
 
    New-WebAppPool -Name $SiteAppPool 
    $manager.CommitChanges()
  }

}

$manager = Get-IISServerManager
if ($manager.Sites[$SiteName] -eq $null) {
    # Site does not exist, create it...
    # ...
    # We use this folder for testing, often as the physical directory for sites
 #   mkdir "C:\Sites" -ErrorAction SilentlyContinue
 #   mkdir "C:\Sites\$SiteFolderPath" -ErrorAction SilentlyContinue
 Execute-WithRetry { 
 
 #Reset-IISServerManager -Confirm:$false
 # In case previous invocations left one open
#Stop-IISCommitDelay -commit $false -WarningAction SilentlyContinue
#Stop-IISCommitDelay -commit $false -WarningAction SilentlyContinue
    New-Item $SiteFolderPath -type Directory -ErrorAction SilentlyContinue
    Set-Content $SiteFolderPath\Default.htm "<h1>Hello $SiteName </h1>"
    New-IISSite -Name $SiteName -BindingInformation :80:$SiteHostName -PhysicalPath $SiteFolderPath
    Set-ItemProperty IIS:\Sites\$SiteName -name applicationPool -value $SiteAppPool
    $manager.CommitChanges()
}
}

if ($manager.Sites[$SiteName].Applications["/MyApp"] -eq $null) {
    # App/virtual directory does not exist, create it...
    # ...
}

$manager.CommitChanges()


# Start App Pool
Execute-WithRetry { 
    $state = Get-WebAppPoolState $SiteAppPool
    if ($state.Value -eq "Stopped") {
        Write-Host "Application pool is stopped. Attempting to start..."
        Start-WebAppPool $SiteAppPool
    }
}

$headers = @{}
$headers.Add("Host",$SiteHostName)
Invoke-WebRequest -Uri http://localhost/ -Headers $headers | Format-Table Content, StatusCode

# Complete