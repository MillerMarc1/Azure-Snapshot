# Azure-Snapshot

![](https://img.shields.io/badge/Category-Compute-lightgrey)
![](https://img.shields.io/badge/Code-PowerShell-blue)
![](https://img.shields.io/badge/Cloud-Azure-blue)
![](https://img.shields.io/badge/Tools-Automation_Account-orange)
![](https://img.shields.io/badge/Tools-Key_Vault-gold)
![](https://img.shields.io/badge/Version-1.0.0-orange)

This project is meant to take snapshots of disks in Azure and delete them based on various rules.

## ❓ Description

Azure Snapshots includes two different scripts:

- takeSnapshot.ps1
- deleteSnapshot-expTag.ps1
*takeSnapshot.ps1* - takes in user input and takes a snapshot of disks attached to a VM.
*deleteSnapshot-expTag.ps1* - deletes snapshots based on the "Expiration" tag value. This value is applied when taking a snapshot with takeSnapshot.ps1

## 🎯 Purpose

This project is meant to facilitate the process of taking snapshots and deleting snapshots that are no longer needed. A snapshot that needs to be kept can be marked with the {Delete: No} flag and the delete script will not remove it. By implementing these scripts into the Azure environment, manual snapshots can be easily taken and are deleted accordingly.

## 🔨 Tools & Technologies 🧰

- Azure Resource Group
- Azure Automation Account
- Azure Key Vault
- PowerShell scripts

## 🏗️ Setup ✔️

Setup of this project involves four steps

- Creating a Resource Group
- Setting up a Key Vault
- Setting up an Automation Account
- Adding the three scripts

1. Create a Resource Group to hold the resources required for the project.
2. Create a key vault and store the password for the email account that will send the report emails.
3. Create an Automation Account and a managed identity that is allowed to:
    - Access the Key Vault
    - Take Snapshots
    - Delete Snapshots
4. Create two runbooks within the Automation Account and add the scripts.

Remember:

- Add a schedule to your delete runbook.
- Replace variable values in the scripts with your specific values.
