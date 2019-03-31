Param(
    [string]$UnitAbbrev,
    [string]$ou
)

Import-Module ActiveDirectory
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"
}

#Change these for your site
$SiteCode = "MMS" # Site code
$SiteServer = "sitesrv" # SMS Provider machine name
#Because I'm bad at programming, I've hardcoded the domain name and group naming scheme into the script
#As well as the OU location that groups are created in
#Find and replace will be your friend :)

if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer
}

#https://social.technet.microsoft.com/Forums/Lync/en-US/ab0eaba5-2bb4-47f1-85d1-224066d0f78b/powershell-modify-advanced-security-properties-of-a-security-group?forum=ITCG
function New-ADACE {
   Param([System.Security.Principal.IdentityReference]$identity,
   [System.DirectoryServices.ActiveDirectoryRights]$adRights,
   [System.Security.AccessControl.AccessControlType]$type,
   [Guid]$Guid)

   $help = @"
   $identity
      System.Security.Principal.IdentityReference
      http://msdn.microsoft.com/en-us/library/system.security.principal.ntaccount.aspx
   $adRights
      System.DirectoryServices.ActiveDirectoryRights
      http://msdn.microsoft.com/en-us/library/system.directoryservices.activedirectoryrights.aspx
   $type
      System.Security.AccessControl.AccessControlType
      http://msdn.microsoft.com/en-us/library/w4ds5h86(VS.80).aspx
   $Guid
      Object Type of the property
      The schema GUID of the object to which the access rule applies.
"@
   $ACE = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity,$adRights,$type,$guid)
   $ACE
}

function Add-ManagedByCheckbox([string]$name, [string]$manager) {
    #http://social.technet.microsoft.com/Forums/en-US/ITCG/thread/ab0eaba5-2bb4-47f1-85d1-224066d0f78b
    $myGuid = "bf9679c0-0de6-11d0-a285-00aa003049e2" #GUID for the Members property

    $DN = (Get-ADGroup $name).DistinguishedName
    $ManagedByDN = (Get-ADGroup $manager).DistinguishedName
    # Create ACE to add to object
    $ID = New-Object System.Security.Principal.NTAccount($env:UserDomain,$manager)
    $newAce = New-ADACE $ID "WriteProperty" "Allow" $myGuid
    # Get Object
    $ADObject = [ADSI]"LDAP://$DN"
    # Set Access Entry on Object
    $ADObject.psbase.ObjectSecurity.SetAccessRule($newAce)
    # Set the manageBy property
    $ADObject.Put("managedBy",$ManagedByDN)
    # Commit changes to the backend
    $ADObject.psbase.commitchanges()
}

function New-CMADGroup([string]$name, [string]$manager, [string]$Path) {
    #Write-Host "name: $name"
    #Write-Host "manager: $manager"
    #Write-Host "path: $Path"
    New-ADGroup -GroupScope Global -Name "$name" -ManagedBy $manager -Path $Path | Out-Null
    Start-Sleep -Seconds 15
    Add-ADGroupMember -Identity CM-MMS-AllAdmins -Members "$name" | Out-Null
    Add-ManagedByCheckbox $name $manager
    return test-CMADGroup $name
}

function Test-CMADGroup([string]$name) {
    return Get-ADGroup -LDAPFilter "(SAMAccountName=$name)"
}


#check if OU exists

#first convert the canonical name we give to a DN that we can search for 
#https://gist.github.com/joegasper/3fafa5750261d96d5e6edf112414ae18
$obj = $ou.Replace(',','\,').Split('/')
[string]$DN = "OU=" + $obj[$obj.count - 1]
for ($i = $obj.count - 2;$i -ge 1;$i--){$DN += ",OU=" + $obj[$i]}
$obj[0].split(".") | ForEach-Object { $DN += ",DC=" + $_}

if (-not (Get-ADOrganizationalUnit -LDAPFilter "(distinguishedname=$DN)")) {
    Write-Error "OU $ou doesn't exist, aborting"
    return
}

#check if CMAdmins group exists in AD
if (Test-CMADGroup "$UnitAbbrev-MMS-CMAdmins") {
    Write-Error "Group $UnitAbbrev-MMS-CMAdmins already exists, aborting"
    return
}

#check if CMHelpdesk group exists in AD
if (Test-CMADGroup "$Unitabbrev-MMS-CMHelpdesk") {
    Write-Error "Group $UnitAbbrev-MMS-CMHelpdesk already exists, aborting"
    return
}

#check for base collection
Push-Location $SiteCode`:
if (Get-CMCollection -Name $UnitAbbrev) {
    Write-Error "A collection with the name $UnitAbbrev already exists, aborting"
    return
}
Pop-Location

#check if scope exists
Push-Location $SiteCode`:
if (Get-CMSecurityScope -Name $UnitAbbrev) {
    Write-Error "A scope with the name $UnitAbbrev already exists, aborting"
    return
}
Pop-Location

#check if CMAdmin group exists in SCCM
Push-Location $SiteCode`:
if (Get-CMAdministrativeUser -Name "mms\$UnitAbbrev-mms-CMAdmins") {
    Write-Error "The user mms\$UnitAbbrev-mms-CMAdmins already exists in SCCM, aborting"
    return
}
Pop-Location

#check if CMHelpdesk group exists in SCCM
Push-Location $SiteCode`:
if (Get-CMAdministrativeUser -Name "mms\$UnitAbbrev-mms-CMHelpdesks") {
    Write-Error "The user mms\$UnitAbbrev-mms-CMHelpdesk already exists in SCCM, aborting"
    return
}
Pop-Location

#Create the CMAdmins Group
$result = New-CMADGroup -name "$UnitAbbrev-MMS-CMAdmins" -manager "OITCM-MMS-CMAdmins" -Path "ou=ConfigMgrAdmins" #these are not complete paths
if ($result) {
    Write-Output "Group $UnitAbbrev-MMS-CMAdmins created"
} else {
    Write-Error "Group $UnitAbbrev-MMS-CMAdmins not created, aborting"
    return
}

#Create the CMHelpdesk Group
$result = New-CMADGroup -name "$UnitAbbrev-MMS-CMHelpdesk" -manager "$UnitAbbrev-MMS-CMAdmins" -Path "ou=ConfigMgrHelpdeskUsers,ou=ConfigMgrAdmins" #these are not complete paths
if ($result) {
    Write-Output "Group $UnitAbbrev-MMS-CMHelpdesk created"
} else {
    Write-Error "Group $UnitAbbrev-MMS-CMHelpdesk not created, aborting"
    return
}

#Create the unit base collection

#create the refresh schedule, once a day at a random time between 6PM and 7AM
$AddHours = Get-Random -Minimum 18 -Maximum 31 #offset from today at midnight from 18 to 30 hours
$AddMinutes = get-random -maximum 60
$midnight = Get-Date -Hour 0 -Minute 0
$DateTime = ($midnight).AddMinutes($AddMinutes).AddHours($AddHours)
Push-Location $SiteCode`:
$NewColRefreshSch = New-CMSchedule -RecurInterval Days -RecurCount 1 -Start $DateTime
$null = New-CMDeviceCollection -LimitingCollectionId SMS00001 -Name $UnitAbbrev -Comment "$UnitAbbrev base collection" -RefreshSchedule $NewColRefreshSch -RefreshType Both
Add-CMDeviceCollectionQueryMembershipRule -CollectionName $UnitAbbrev -QueryExpression "select * from SMS_R_System where SMS_R_System.SystemOUName in (""$ou"")" -RuleName $UnitAbbrev
#check if it was actually created
if (Get-CMCollection -Name $UnitAbbrev) {
    Write-Output "Collection with the name $UnitAbbrev created"
} else {
    Write-Error "Collection with the name $UnitAbbrev not created, aborting"
    Pop-Location
    return
}
Pop-Location

#Create the unit scope
Push-Location $SiteCode`:
New-CMSecurityScope -Name $UnitAbbrev -Description "$UnitAbbrev Unit Security Scope" | Out-Null
#add the scope to the DP group
$scope = Get-CMSecurityScope -Name $UnitAbbrev
$mmsdp = Get-CMDistributionPointGroup -Name "MMS System Distribution Points"
Add-CMObjectSecurityScope -Scope $scope -InputObject $mmsdp

if ($scope) {
    Write-Output "Scope $UnitAbbrev created"
} else {
    Write-Error "Scope $UnitAbbrev not created, aborting"
    Pop-Location
    return
}
if (Get-CMObjectSecurityScope -InputObject $mmsdp | Where-Object {$_.CategoryName -eq $UnitAbbrev}) {
    Write-Output "scope $UnitAbbrev added to DP group"
} else {
    write-error "scope $UnitAbbrev not added to DP group, aborting"
    Pop-Location
    return
}
Pop-Location


#create CMAdmin user in SCCM and assign roles and scopes
Push-Location $SiteCode`:
$user = New-CMAdministrativeUser -Name "mms\$UnitAbbrev-mmm-CMAdmins" -RoleName "UNIT Administrator" -CollectionName $UnitAbbrev -SecurityScopeName $UnitAbbrev
start-sleep -Seconds 10

#https://social.technet.microsoft.com/Forums/en-US/6f89a658-a2e8-41b2-97d0-a9fc06b6db5b/creating-admin-users-from-powershell?forum=configmanagersdk
#http://cm12sdk.net/?p=1090
$adminUsers = [wmiclass]"\\$SiteServer\ROOT\SMS\Site_$SiteCode`:SMS_Admin"
$adminUser = $adminUsers.GetInstances() | Where-Object {$_.LogonName -eq "mms\$UnitAbbrev-mms-cmadmins"}

$adminUser.Get()

$aPermission = [wmiclass]"\\$siteserver\ROOT\SMS\Site_$SiteCode`:SMS_APermission"

$cmPerms = $aPermission.psbase.CreateInstance()
$cmPerms.CategoryID = "mms00003"
$cmPerms.CategoryTypeID = 29
$cmPerms.RoleID = "mms00003"

$basePerms = $aPermission.psbase.CreateInstance()
$basePerms.CategoryID = "SMS00UNA"
$basePerms.CategoryTypeID = 29
$basePerms.RoleID = "mms00002"

$unknownPerms = $aPermission.psbase.CreateInstance()
$unknownPerms.CategoryID = "SMS000US"
$unknownPerms.CategoryTypeID = 1
$unknownPerms.RoleID = "mms00002"

$adminUser.Permissions += $cmPerms
$adminUser.Permissions += $basePerms
$adminuser.Permissions += $unknownPerms

$null = $adminUser.Put()

#check if CMAdmin group exists in SCCM
if (Get-CMAdministrativeUser -Name "mms\$UnitAbbrev-mms-CMAdmins") {
    Write-Output "The user mms\$UnitAbbrev-mms-CMAdmins was created"
} else {
    Write-Error "The user mms\$UnitAbbrev-mms-CMAdmins was not created, aborting"
    Pop-Location
    return
}
Pop-Location

#create cmhelpdesk user in sccm and assign roles & scopes
Push-Location $SiteCode`:
$user = New-CMAdministrativeUser -Name "mms\$UnitAbbrev-mms-CMHelpdesk" -RoleName "UNIT Helpdesk" -CollectionName $UnitAbbrev -SecurityScopeName ("Default",$UnitAbbrev)
#check if CMhelpdesk group exists in SCCM
if (Get-CMAdministrativeUser -Name "mms\$UnitAbbrev-mms-CMHelpdesk") {
    Write-Output "The user mms\$UnitAbbrev-mms-CMHelpdesk was created"
} else {
    Write-Error "The user mms\$UnitAbbrev-mms-CMHelpdesk was not created, aborting"
    Pop-Location
    return
}
Pop-Location

Write-Output "Scope created for unit $UnitAbbrev"