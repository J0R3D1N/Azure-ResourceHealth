[cmdletbinding()]
param(
    $resourceGroupName = "lab-automation-rg",
    $storageAccountName = "automationstgacct",
    $tableName = "ResourceHealthTable"
)

Function Get-StringHash {
    Param(
        [String] $String,
        [ValidateSet("MD5","SHA","SHA1","SHA256","SHA384","SHA512")]
        $hashType = "MD5"
    )
        $StringBuilder = New-Object System.Text.StringBuilder
        [System.Security.Cryptography.HashAlgorithm]::Create($hashType).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($String)) | ForEach-Object {
            [Void]$StringBuilder.Append($_.ToString("x2"))
        }
        Return $StringBuilder.ToString()
}

$stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
$maxRunTime = [System.TimeSpan]::FromMinutes(55)

try {
    # Get the connection "AzureRunAsConnection "
    $svcPrncpl = Get-AutomationConnection -Name "AzureRunAsConnection"
    $tenantId = $svcPrncpl.tenantId
    $subscriptionId = $svcPrncpl.subscriptionId
    $appId = $svcPrncpl.ApplicationId
    $crtThmprnt = $svcPrncpl.CertificateThumbprint
    Add-AzureRmAccount -ServicePrincipal -TenantId $tenantId -ApplicationId $appId -CertificateThumbprint $crtThmprnt -EnvironmentName AzureUsGovernment | Out-Null
 }
catch {
    if (!$svcPrncpl) {
        $ErrorMessage = "Connection AzuerRunAsConnection not found."
        throw $ErrorMessage
    }
    else {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

$storageContext = (Get-AzureRmStorageAccount -Name $storageAccountName -ResourceGroupName $resourceGroupName).Context
$storageTable = Get-AzureStorageTable -Name $tableName -Context $storageContext -ErrorAction SilentlyContinue

If (-NOT $storageTable) {
    $storageTable = New-AzureStorageTable -Name $tableName -Context $storageContext
}

$restUri = ('https://management.usgovcloudapi.net/subscriptions/{0}/Providers/Microsoft.ResourceHealth/availabilityStatuses?api-version=2015-01-01' -f $subscriptionId)
$iterationCounter = 0
$stopFlag = $false

While ($stopFlag -eq $false) {
    $iterationCounter++
    Write-Output ("`n`rStarting Resource Health Tracking: Iteration {0}" -f $iterationCounter)
    $azureContext = Get-AzureRmContext
    $tenantId = (Get-AzureRmSubscription -SubscriptionId $subscriptionId).TenantId
    $tokenCache = $azureContext.TokenCache
    $cachedTokens = $tokenCache.ReadItems() | Where-Object {$_.TenantId -eq $tenantId} | Sort-Object -Property ExpiresOn -Descending
    $accessToken = $cachedTokens[0].AccessToken
    $header = @{
        Authorization = "Bearer " + $accessToken
    }
    try {
        $timeStamp = [System.DateTime]::UtcNow
        $restCallTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $resourceStatuses = Invoke-RestMethod -Method Get -Uri $restUri -Headers $header
        $restCallTimer.Stop()
        Write-Output ("Invoke Rest Method completed in: {0} hrs {1} min {2} sec {3} ms" -f $restCallTimer.Elapsed.Hours,$restCallTimer.Elapsed.Minutes,$restCallTimer.Elapsed.Seconds,$restCallTimer.Elapsed.Milliseconds)

        $parseTimer = [system.Diagnostics.Stopwatch]::StartNew()
        $resourceTable = $resourceStatuses.value | Select-Object id,`
            @{l="rowKey";e={(Get-StringHash -String $_.id -hashType SHA256)}},`
            @{l="resourceProvider";e={($_.id -Split "/providers/")[1].Split("/")[0]}},`
            @{l="resourceType";e={($_.id -Split "/providers/")[1].Split("/")[1]}},`
            @{l="resourceName";e={($_.id -Split "/providers/")[1].Split("/")[2]}},`
            @{l="resourceGroupName";e={($_.id -Split "/resourceGroups/")[1].Split("/")[0]}},`
            @{l="availabilityState";e={$_.properties.availabilitystate}},`
            @{l="title";e={$_.properties.title}},`
            @{l="summary";e={$_.properties.summary}},`
            @{l="reasonType";e={$_.properties.reasonType}},`
            @{l="occuredTimeUTC";e={([DateTime]$_.properties.occuredTime).ToUniversalTime()}},`
            @{l="reasonChronicity";e={$_.properties.reasonChronicity}},`
            @{l="reportedTimeUTC";e={([DateTime]$_.properties.reportedTime).ToUniversalTime()}} -ExcludeProperty properties
        $parseTimer.Stop()
        Write-Output ("Resource Parsing completed in: {0} hrs {1} min {2} sec {3} ms" -f $parseTimer.Elapsed.Hours,$parseTimer.Elapsed.Minutes,$parseTimer.Elapsed.Seconds,$parseTimer.Elapsed.Milliseconds)

        $addTableRowTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Foreach ($resource in $resourceTable) {
            $tableParameters = [Ordered]@{
                table = $storageTable
                partitionKey = $resource.resourceType
                rowKey = $resource.rowKey
                property = [Ordered]@{
                    lastRunTimestamp = $timeStamp
                    subscriptionId = $subscriptionId
                    resourceGroupName = $resource.ResourceGroupName
                    resourceProvider = $resource.resourceProvider
                    resourceType = $resource.resourceType
                    resourceName = $resource.resourceName
                    availabilityState = $resource.availabilityState
                    title = $resource.title
                    summary = $resource.summary
                    reasonType = $resource.reasonType
                    occuredTimeUTC = $resource.occuredTimeUTC
                    reasonChronicity = $resource.reasonChronicity
                    reportedTimeUTC = $resource.reportedTimeUTC
                    resourceId = $resource.id
                }
            }

            Add-StorageTableRow @tableParameters -UpdateExisting | Out-Null
        }
        $addTableRowTimer.Stop()
        Write-Output ("Adding Resources to Table completed in: {0} hrs {1} min {2} sec {3} ms" -f $addTableRowTimer.Elapsed.Hours,$addTableRowTimer.Elapsed.Minutes,$addTableRowTimer.Elapsed.Seconds,$addTableRowTimer.Elapsed.Milliseconds)
        Write-Output ("Current runbook duration: {0} hrs {1} min {2} sec {3} ms" -f $stopWatch.Elapsed.Hours,$stopWatch.Elapsed.Minutes,$stopWatch.Elapsed.Seconds,$stopWatch.Elapsed.Milliseconds)
    }
    catch [System.Net.WebException] {
        Write-Warning ("Triggered System.Net.WebException")
        Write-Warning @_
    }
    catch {$PSCmdlet.ThrowTerminatingError($PSItem)}

    If ($stopWatch.Elapsed.TotalMinutes -ge $maxRunTime.TotalMinutes) {
        Write-Output ("Max ticks elapsed, setting Stop Flag to TRUE")
        $stopFlag = $true
    }
    Else {
        $elapsedTimeRemaining = $maxRunTime - $stopWatch.Elapsed
        Write-Output ("Runbook runtime remaining: {0} min {1} sec {2} ms" -f $elapsedTimeRemaining.Minutes,$elapsedTimeRemaining.Seconds,$elapsedTimeRemaining.Milliseconds)
    }
    Write-Output "Sleeping for 120 Seconds"...
    Start-Sleep -seconds 15
}
$Stopwatch.Stop()

