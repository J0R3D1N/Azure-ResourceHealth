$subscriptionId = "96f889ee-3654-4f61-b369-5f93574edc37"
$resourceGroupName = "VHICDEV-DEVTEST-INT-EAST-RG"
$resourceId = "subscriptions/96f889ee-3654-4f61-b369-5f93574edc37/resourceGroups/VHICDEV-DEVTEST-INT-EAST-RG/providers/Microsoft.Compute/virtualMachines/VAAZVIAMTSTSHRD"
$vmname = "VAAZVIAMTSTSHRD"

Get-AzureRmSubscription -SubscriptionId  $subscriptionId | Select-AzureRmSubscription | Out-Null
$resourceGroups = Get-AzureRmResourceGroup | % {$_.resourcegroupname}

$azureContext = Get-AzureRmContext
$tenantId = (Get-AzureRmSubscription -SubscriptionId $subscriptionId).TenantId
$tokenCache = $azureContext.TokenCache
$cachedTokens = $tokenCache.ReadItems() | Where-Object {$_.TenantId -eq $tenantId} | Sort-Object -Property ExpiresOn -Descending
$accessToken = $cachedTokens[0].AccessToken
$header = @{
    Authorization = "Bearer " + $accessToken
}


$restUri_sub = ('https://management.usgovcloudapi.net/subscriptions/{0}/providers/Microsoft.ResourceHealth/availabilityStatuses?api-version=2015-01-01' -f $subscriptionId)
$restUri_rg = ('https://management.usgovcloudapi.net/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.ResourceHealth/availabilityStatuses?api-version=2015-01-01' -f $subscriptionId,$resourceGroupName)
$restUri_vm = ('https://management.usgovcloudapi.net/{0}/providers/Microsoft.ResourceHealth/availabilityStatuses/current?api-version=2015-01-01' -f $resourceId)
$restUri_vmhistory = ('https://management.usgovcloudapi.net/{0}/providers/Microsoft.ResourceHealth/availabilityStatuses?api-version=2015-01-01' -f $resourceId)

Write-Host "Getting Resource Health for the subscription"
$substatus = Invoke-RestMethod -Method Get -Uri $restUri_sub -Headers $header
Write-Host ("Getting Resource Health for the {0} Resource Group" -f $resourceGroupName)
$rgstatus = Invoke-RestMethod -Method Get -Uri $restUri_rg -Headers $header
Write-Host ("Getting Resource Health for the {0} Resource" -f $vmname)
$vmstatus = Invoke-RestMethod -Method Get -Uri $restUri_vm -Headers $header
Write-Host ("Getting Resource Health History for {0} Resource" -f $vmname)
$vmhistorystatus = Invoke-RestMethod -Method Get -Uri $restUri_vmhistory -Headers $header

























[System.Collections.ArrayList]$resourceStatuses = @()
Foreach ($resourceGroup in $resourceGroups) {
    Write-Output ("Getting Resource Health for: {0}" -f $resourceGroup)
    $restUri = ('https://management.usgovcloudapi.net/subscriptions/7c2f587d-7a26-449f-a3de-7e2890bf3613/resourceGroups/{0}/providers/Microsoft.ResourceHealth/availabilityStatuses?api-version=2015-01-01' -f $resourceGroup)
    try{$rgStatuses = Invoke-RestMethod -Method Get -Uri $restUri -Headers $header}
    catch [System.Net.WebException]{
        Write-Warning "$restUri"
        Write-Warning @_
    }
    $rgStatuses.value | % {$resourceStatuses.Add($_) | Out-Null}
    #Start-Sleep -Seconds 30
}