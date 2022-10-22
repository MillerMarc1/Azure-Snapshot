# Powershell script to delete snapshots by Retention Date
 
# Logging into Azure account
Disable-AzContextAutosave | Out-Null
Connect-AzAccount -Identity | Out-Null
 
$date = Get-Date -Format 'MM-dd-yyyy'
 
#Create a table for storage report metrics
$table = New-Object System.Data.DataTable "SnapshotDeletionLog"
$col1 = New-Object System.Data.DataColumn SnapshotName
$col2 = New-Object System.Data.DataColumn ResourceGroupName
$col3 = New-Object System.Data.DataColumn TimeCreated
$col4 = New-Object System.Data.DataColumn VmName
$col5 = New-Object System.Data.DataColumn SourceDisk
$table.Columns.Add($col1)
$table.Columns.Add($col2)
$table.Columns.Add($col3)
$table.Columns.Add($col4)
$table.Columns.Add($col5)
 
$snapshots = Get-AzSnapshot | Where-Object {($null -ne $_.Tags['Expiration']) -and ($_.Tags['Expiration'] -le $date) -and ($_.Tags['Delete'] -notlike "No")}
 
for ($i = 0; $i -lt $snapshots.Count; $i++) {
    $snapshotName = $snapshots[$i].Name
    $snapshotRgName = $snapshots[$i].ResourceGroupName
    $VmName = $snapshots[$i].Tags['VM_Name']
    $SourceDisk = $snapshots[$i].Tags['Disk_Name']
    $TimeCreated = $snapshots[$i].TimeCreated
 
    #Add metrics to table
    $row = $table.NewRow()
    $row.SnapshotName = $snapshotName
    $row.ResourceGroupName = $snapshotRgName
    $row.TimeCreated = $timeCreated
    $row.VmName = $VmName
    $row.SourceDisk = $SourceDisk
    $table.Rows.Add($row)
 
    "Snapshot $snapshotName in $snapshotRgName will be deleted"
    Remove-AzSnapshot -ResourceGroupName $snapshotRgName -SnapshotName $snapshotName -Force -AsJob
}
 
#Export report to CSV
$date = Get-Date -Format "MM-dd-yyyy"
$logFile = "SnapshotDeletionLog-" + $date + ".CSV"
 
$table | Export-Csv -path $logFile -NoTypeInformation -Append
 
# Mailbox credentials
$keyVaultSecret = Get-AzKeyVaultSecret -VaultName "{Vault Name}" -Name "{Secret Name}" -AsPlainText
 
#Send email notification
$azureAccountName ="{...}@{...}.com"
$azurePassword = ConvertTo-SecureString $keyVaultSecret -AsPlainText -Force
 
$psCred = New-Object System.Management.Automation.PSCredential($azureAccountName, $azurePassword)
 
Send-MailMessage -To '{...}@{...}.com' , '{...}@{...}.com' -Subject "Snapshot-Deletion-Log" -Body "The following report shows the list of deleted snapshots, based on its expiration date tag." -Attachments $logFile -UseSsl -Port {PORT} -SmtpServer 'smtp.{SMTP server name}.com' -From $azureAccountName -BodyAsHtml -Credential $psCred
 
# Get all jobs and wait on them.
Get-Job | Wait-Job
$Jobs = Get-Job
 
$ScriptResult = "Successful"
 
if ($null -ne $Jobs) {
    foreach ($Job in $Jobs) {
        if ($Job.State -eq "Failed") {
            $ScriptResult = "Failed"
        }
    }
    if ($ScriptResult -eq "Failed") {
        "Snapshot Deletion Failed"
    } else {  
        "Snapshot were deleted successfully"
    }
}