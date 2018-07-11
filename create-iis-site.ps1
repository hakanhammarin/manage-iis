# The following code will create an IIS site and it associated Application Pool. 
# Please note that you will be required to run PS with elevated permissions. 
# Visit http://ifrahimblog.wordpress.com/2014/02/26/run-powershell-elevated-permissions-import-iis-module/ 

# set-executionpolicy unrestricted
# https://octopus.com/blog/iis-powershell#retry-retry-retry

clear

# $SiteHostName = "www.localhost.local" 

$SiteHostName = Read-Host -Prompt "Enter Site" 
$SiteFolderPath = "D:\Sites\$SiteHostName"              # Website Folder
$SiteRoot = "D:\Sites\"
# $AMEACurrentVersionRoot = $SiteRoot+"_AMEaWEb_v20180711_002"
$AMEACurrentVersionRoot = $SiteRoot+"_current.ameaweb.se"



#$SiteAppPool = "MyAppPool"                  # Application Pool Name
$SiteAppPool = $SiteHostName                 # Application Pool Name
#$SiteName = "MySite"                        # IIS Site Name
$SiteName = $SiteHostName                      # IIS Site Name
                # Host Header

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
 #mkdir $SiteFolderPath -ErrorAction SilentlyContinue
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
    # New-Item $SiteFolderPath -type Directory -ErrorAction SilentlyContinue
# cmd mklink /J $SiteRoot+$SiteName $AMEaCurrentVersionRoot
New-Item -Path $SiteRoot$SiteName -ItemType Junction -Value $AMEACurrentVersionRoot
#    Set-Content $SiteFolderPath\Default.htm "Site: $SiteName"
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
Invoke-WebRequest -Uri http://localhost/healthcheck.htm -Headers $headers | Format-Table Content, StatusCode

# dir Cert:\LocalMachine/my

$cert = (Get-ChildItem cert:\LocalMachine\My   | where-object { $_.Subject -like "*ameaweb.se*" }   | Select-Object -First 1).Thumbprint

"Cert Hash: " + $cert

# http.sys mapping of ip/hostheader to cert
$guid = [guid]::NewGuid().ToString("B")
netsh http add sslcert hostnameport="${SiteHostName}:443" certhash=$cert certstorename=MY appid="$guid"

# iis site mapping ip/hostheader/port to cert - also maps certificate if it exists
# for the particular ip/port/hostheader combo
New-WebBinding -name $SiteHostName -Protocol https  -HostHeader $SiteHostName -Port 443 -SslFlags 1

# netsh http delete sslcert hostnameport="${hostname}:443"
# netsh http show sslcert


# Complete
