# PowerShell Utilities for Administration ⚙️

A collection of small, practical PowerShell scripts used for day-to-day administration of Azure/Entra ID, Exchange Online, SharePoint Online, and Windows Server environments. These scripts are intended to save time by automating common tasks — many were created by combining best-practice commands and public examples.

---

## 📋 Table of Contents

- [PowerShell Utilities for Administration ⚙️](#powershell-utilities-for-administration-️)
  - [📋 Table of Contents](#-table-of-contents)
  - [Quick Summary](#quick-summary)
  - [Repository Layout 🗂️](#repository-layout-️)
  - [Prerequisites 🔧](#prerequisites-)
  - [Usage ▶️](#usage-️)
  - [Examples ✏️](#examples-️)
  - [Contributing 🤝](#contributing-)
  - [Security \& Privacy ⚠️](#security--privacy-️)

---

## Quick Summary

This repo contains small, focused scripts organized by area:

- **Entra ID**: user and group automation (create users, add members to groups, remove domain suffixes, templates for CSV input).
- **Exchange Online**: mail/contact/group management helpers (create distribution groups, add aliases, update contacts from CSVs).
- **SharePoint Online**: tenant/OneDrive provisioning scripts.
- **Windows Server**: on-prem utilities for user rights, processes, and proxy address management.

Each script typically includes a short header describing purpose, parameters, and sample usage—open the top of the file or use Get-Help to view it.

---

## Repository Layout 🗂️

Top-level directories and notable files:

- `Entra ID/` — AddMemberToAllSecurityGroups.ps1, CreateUsersFromCSV.ps1, create-users-template.csv.tpl, RemoveUsersDomain.ps1, etc.
- `Exchange Online/` — scripts for distribution groups, mail contacts, aliases, and helpers (e.g. `Create-DistributionGroupsFromCSV.ps1`).
- `SharepointOnline/` — `Pre-provisionOneDrive.ps1` and related utilities.
- `Windows Server/` — server-side helper scripts (e.g. `Repair-UserRights.ps1`).

Also included are sample CSV files and templates (e.g. `create-users-template.csv.tpl`, `new-user-list.csv`) to help format inputs.

---

## Prerequisites 🔧

Before running scripts, ensure you have:

- PowerShell 7+ (recommended) or Windows PowerShell where required.
- Required modules installed as appropriate for each script (examples):
  - `ExchangeOnlineManagement` (for Exchange Online scripts)
  - `PnP.PowerShell` or `SharePointOnline` management modules (for SharePoint scripts)
  - `Microsoft.Graph` / `AzureAD` (for Entra ID scripts)

Install modules when needed, for example:

```powershell
Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser
Install-Module -Name PnP.PowerShell -Scope CurrentUser
Install-Module -Name Microsoft.Graph -Scope CurrentUser
```

Check the header comments at the top of each script for exact requirements and recommended versions.

---

## Usage ▶️

1. Open PowerShell with the appropriate permissions (e.g., admin where required).
2. Connect to the service you'll manage (examples):
   - `Connect-ExchangeOnline` for Exchange Online
   - `Connect-PnPOnline` or `Connect-SPOService` for SharePoint
   - `Connect-MgGraph` or `Connect-AzureAD` for Entra ID
3. Run the script (example):

```powershell
# From the repository root
PowerShell -NoProfile -ExecutionPolicy Bypass -File "./Entra ID/CreateUsersFromCSV.ps1" -CsvPath "./Entra ID/new-user-list.csv"
```

Note: script parameter names may vary — consult the script header, or run `Get-Help .\Path\To\Script.ps1 -Full`.

---

## Examples ✏️

- Create users from CSV (example flow):
  1. Edit `Entra ID/create-users-template.csv.tpl` to match your tenant fields.
  2. Run the create users script after connecting to Graph/Azure AD.

- Add aliases or update distribution groups:
  1. Connect with `Connect-ExchangeOnline`.
  2. Run `Exchange Online/Add-MailContactsFromCSV.ps1` or `Create-DistributionGroupsFromCSV.ps1` with the appropriate CSV.

---

## Contributing 🤝

Contributions are welcome. A few guidelines:

- Add a short header to new scripts with: purpose, parameters, required modules, example usage, and author.
- Keep scripts idempotent where possible and add safety checks (e.g. `-WhatIf`, `-Confirm` where it makes sense).
- Open an issue to discuss non-trivial changes or improvements.

---

## Security & Privacy ⚠️

- Do not hard-code credentials or secrets into scripts. Use interactive connection cmdlets and managed identities where available.
- Test scripts in a non-production environment first.
- Be careful when running destructive operations (deletes, mass updates) — include dry-run steps.

---

Thanks for using this repo
