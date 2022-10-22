Param # Input Parameters
(
    [Parameter (Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(1,64)] # Validate length of VM Name
    [ValidatePattern("(^([a-zA-Z0-9]{1}[-]?){1,63}[a-zA-Z0-9]{1}$)|(^[a-zA-Z0-9]{1}$)")] # Regex to validate the VM Name
    [string] $VmName ,
 
    [Parameter (Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern("(^([a-zA-Z0-9_()\-.]{1}[-]?){1,89}[a-zA-Z0-9_()\-]{1}$)|(^[a-zA-Z0-9_()\-]{1}$)")] # Regex to validate the Resource Group Name
    [ValidateLength(1,90)] # Validate length of RG Name
    [string] $resourceGroupName ,
 
    [Parameter (Mandatory= $false)]
    [ValidateSet("Yes","No")]
    [string] $OsSnapshot = "No" ,
 
    [Parameter (Mandatory= $false)]
    [ValidateSet("Yes","No")]
    [string] $dataDiskSnapshot = "Yes" ,
 
    [Parameter (Mandatory= $false)]
    [ValidateRange(1,365)] # Adjust Range if needed
    [int] $RetentionDays = 14 ,
 
    [Parameter (Mandatory= $false)]
    [ValidateSet("Yes","No")]
    [string] $restartVM = "Yes" ,
 
    [Parameter (Mandatory= $false)]
    [ValidateSet("Yes","No")]
    [string] $shutdown = "No"
)
       
# Ensure inputs are correct and that a usable snapshot can be taken
# Azure Login
Disable-AzContextAutosave | Out-Null
Connect-AzAccount -Identity | Out-Null
 
# Validate RG
Write-Verbose "Validatig VM exists in specified resource group."
try {
    $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $VmName -ErrorAction Stop
} catch {
    Write-Verbose "Incorrect VM/Resource Group"
    $vm = Get-AzVM -Name $VmName -ErrorAction Stop
    if ($null -eq $vm) { # VM name cannot be found in the subscription
        Write-Error "VM does not exist"
        exit
    } else { # If the VM exists but the resource group does not match the input
        $correctResourceGroupName = $vm.ResourceGroupName
        Write-Error "The VM does not exist in the specified Resource Group. Did you mean ResourceGroupName = $correctResourceGroupName"
        exit
    }
}
Write-Verbose "VM exists in specified resource group"
 
# Validate VM
$VmOs = $vm.StorageProfile.OsDisk.OsType
$vmStatus = Get-AzVM -ResourceGroupName $resourceGroupName -Name $VmName -Status
 
# Check power state of the system
if ($VmStatus.Statuses | Where-Object Code -match "PowerState/running") {
    Write-Output """$VmName"" is currently running"
    if ($VmOs -eq "Windows") { # If the disk belongs to a windows system, snapshots can be taken while VM is running
        Write-Output "Since this is a Windows system, snapshots can be taken with a running system"
    } else {
        if ($OsSnapshot -like "yes" -and $dataDiskSnapshot -like "no") { # The OS Disk does not have LVM enabled
            Write-Output "Since we are only taking a snapshot of the OS disk, the VM can remain powered on"
        } else {
            if ($shutdown -like "No") {
                Write-Error "Since this is a Linux system and you are snapshotting a data disk, LVM may be enabled. You need to set the Shutdown option to ""Yes"" to continue"
                exit
            } else { # LVM may be enabled, system is powered off
                Write-Output "Since this is a Linux system and you are snapshotting a data disk, LVM may be enabled. The system will be powered off"
                Write-Output "Shutting-down VM..."
                Stop-AzVM -ResourceGroupName $resourceGroupName -Name $VmName -StayProvisioned -Force | Out-Null
                Write-Output "VM has been shutdown."
            }
        }
    }
}

# Power off VM if shutdown parameter is Yes
$vmStatus = Get-AzVM -ResourceGroupName $resourceGroupName -Name $VmName -Status
if ($VmStatus.Statuses | Where-Object Code -match "PowerState/running") {
    if ($shutdown -like "Yes") {
        Write-Output "Shutting-down VM..."
        Stop-AzVM -ResourceGroupName $resourceGroupName -Name $VmName -StayProvisioned -Force | Out-Null
        Write-Output "VM has been shutdown."
    }
} else {
    Write-Output "The system is shutdown."
}
       
# Validate disks
foreach ($disk in $vmStatus.Disks) {
    $disk = Get-AzDisk -DiskName $disk.name
    $diskName = $disk.Name
    $diskResourceGroupName = $disk.ResourceGroupName
    $diskOsType = $disk.OsType
    $OsDiskName = $vm.StorageProfile.OsDisk.Name

    # Check if disks exist in a different resource group
    if ($diskResourceGroupName -ne $resourceGroupName) {
        Write-Warning "$diskName is in Resource Group $diskResourceGroupName and its VM is in Resource Group $resourceGroupName (This does not impact the snapshot, but it will be stored in the disks RG and not the VMs RG)"
    }
 
    # Check if disks are shared
    if ($null -ne $disk.MaxShares) {
        Write-Error "Taking a snapshot of a shared disk is not currently supported. No snapshots have been taken"
        exit
    }
   
    # Verify OS and Data Disk
    if ($OsSnapshot -like "Yes" -and $diskName -eq $OsDiskName) {
        Write-Output "A snapshot of OS disk ""$diskName"" will be taken"
    } elseif ($dataDiskSnapshot -like "Yes" -and $null -eq $diskOsType) {
        Write-Output "A snapshot of data disk ""$diskName"" will be taken"
    }
}
Write-Output "Validation has been completed...Proceeding to take snapshot(s)"
Write-Output "`n`n"
       
# Take the snapshot
$creationDate = Get-Date
$expirationDate = $creationDate.AddDays($RetentionDays) | Get-Date -Format "MM-dd-yyyy"
$creationDate = Get-Date $creationDate -Format "MM-dd-yyyy--hh-mm-ss-tt"
 
$location = (Get-AzVM -ResourceGroupName $resourceGroupName -Name $VmName).Location
 
$osSnapName = ""
# OS Disk Snaphot
if ($OsSnapshot -like "Yes") {
    $OsDiskName = (Get-AzVM -Name $VmName -ResourceGroupName $resourceGroupName).StorageProfile.OsDisk.Name
    $OsDisk = Get-AzDisk -Name $OsDiskName
    $OsDiskID = $OsDisk.Id
    $OsDiskRgName = $OsDisk.ResourceGroupName
 
    $tags = @{
        VM_Name="$VmName";
        Disk_Name="$OsDiskName";
        Disk_Type="OS";
        Expiration="$expirationDate";
    }
           
    $OsDiskSnapshotConfig = New-AzSnapshotConfig -SourceUri $OsDiskID -Location $location -CreateOption "Copy" -SkuName Standard_LRS -Tag $tags
           
    $snapshotName = "snap-" + $creationDate + "-" + $OsDiskName
 
    if ($snapshotName.Length -ge 80) {
        $snapshotName = $snapshotName.Substring(0, 80)
    }
 
    try {
        Write-Output "Taking ""$snapshotName"" snapshot..."
        New-AzSnapshot -Snapshot $OsDiskSnapshotConfig -SnapshotName $snapshotName -ResourceGroupName $OsDiskRgName -ErrorAction Stop | Out-Null
        Write-Output "Snapshot has been taken."
    } catch {
        Write-Error "Snapshot Failed..."
        Write-Error $Error[0]
    }
    $osSnapName = $snapshotName
}
 
$dataDiskArr = New-Object System.Collections.ArrayList
# Data Disks Snapshot
if ($dataDiskSnapshot -like "Yes") {
    $dataDisks = (Get-AzVM -Name $VmName -ResourceGroupName $resourceGroupName).StorageProfile.DataDisks.Name # There might be a collection of data disks
    foreach ($dataDisk in $dataDisks) {
        $dataDiskObj = Get-AzDisk -Name $dataDisk
        $dataDiskID = $dataDiskObj.Id
        $dataDiskRgName = $dataDiskObj.ResourceGroupName
 
        $tags = @{
            VM_Name="$VmName";
            Disk_Name="$dataDisk";
            Disk_Type="Data Disk";
            Expiration="$expirationDate";
        }
               
        $dataDiskSnapshotConfig = New-AzSnapshotConfig -SourceUri $dataDiskID -Location $location -CreateOption "Copy" -SkuName Standard_LRS -Tag $tags
               
        $snapshotName = "snap-" + $creationDate + "-" + $dataDisk
 
        if ($snapshotName.Length -ge 80) {
            $snapshotName = $snapshotName.Substring(0, 80)
        }
               
        try {
            Write-Output "Taking ""$snapshotName"" snapshot..."
            New-AzSnapshot -Snapshot $dataDiskSnapshotConfig -SnapshotName $snapshotName -ResourceGroupName $dataDiskRgName -ErrorAction Stop | Out-Null
            Write-Output "Snapshot has been taken."
        } catch {
            Write-Error "Snapshot Failed..."
            Write-Error $Error[0]
        }
        $dataDiskArr.Add($snapshotName) | Out-Null
    }
}
 
# Update the VM Status after Snapshot is taken
$vmStatus = Get-AzVM -ResourceGroupName $resourceGroupName -Name $VmName -Status
 
if ($VmStatus.Statuses | Where-Object Code -match "PowerState/stopped") {
    if ($restartVM -like "Yes"){
        Write-Output "Restarting VM..."
        Start-AzVM -ResourceGroupName $resourceGroupName -Name $VmName | Out-Null
        Write-Output "VM is up!"
    }
} else {
    Write-Output "The system is already running."
}
 
Write-Output "`n`n"
 
# Print results
if ($OsSnapshot -like "Yes") {
    try {
        $osSnap = Get-AzSnapshot -SnapshotName $osSnapName -ErrorAction Stop
        $name = $osSnap.Name
        $rgName = $osSnap.ResourceGroupName
        Write-Output "OS Disk snapshot ""$name"" in Resource Group ""$rgName"" has been created."
    } catch {
        Write-Error "Something went wrong...could not find OS Disk Snapshot ""$osSnapName"""
        Write-Error $Error[0]
    }
}
 
if ($dataDiskSnapshot -like "Yes") {
    try {
        foreach ($dataDisk in $dataDiskArr){
            $dataDiskSnap = Get-AzSnapshot -SnapshotName $dataDisk -ErrorAction Stop
            $name = $dataDiskSnap.Name
            $rgName = $dataDiskSnap.ResourceGroupName
            Write-Output "Data Disk snapshot ""$name"" in Resource Group ""$rgName"" has been created."
        }
    } catch {
        Write-Error "Something went wrong...could not find Data Disk Snapshot ""$dataDisk"""
        Write-Error $Error[0]
    }
}