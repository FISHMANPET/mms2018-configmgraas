
$date = Get-Date -Format yyyyMMdd
$certpassword = "password" | ConvertTo-SecureString -AsPlainText -Force
$bootpassword = "password" |ConvertTo-SecureString -AsPlainText -Force
$certpath = "mediacert.pfx"
$isodir = "BootMedia"
$archivedir = "_archive"

$isos = Get-ChildItem -file -filter *.iso $isodir
foreach ($iso in $isos) {
    if ($iso.Name -like "mms-bootmedia-x*") {
        Move-Item $iso.FullName "$isodir\$archivedir"
    }
}

Import-Module (Join-Path $(Split-Path $env:SMS_ADMIN_UI_PATH) ConfigurationManager.psd1)
Push-Location MMS:

$bootimagex64 = Get-CMBootImage -Id "MMS00005"
$bootimagex86 = Get-CMBootImage -Id "MMS00004"
$dp = Get-CMDistributionPoint -SiteSystemServerName "mms-node1"
$mp = Get-CMManagementPoint -SiteSystemServerName "mms-node*" | Where-Object {$PSItem.NetworkOSPath -notlike "*mmsnode3*"}
New-CMBootableMedia -BootImage $bootimagex86 -DistributionPoint $dp -ManagementPoint $mp -AllowUacPrompt -AllowUnknownMachine -CertificatePath $certpath -CertificatePassword $certpassword -MediaPassword $bootpassword -MediaMode Dynamic -MediaType CdDvd -Path "$isodir\MMS-BootMedia-x86-$date.iso"
New-CMBootableMedia -BootImage $bootimagex64 -DistributionPoint $dp -ManagementPoint $mp -AllowUacPrompt -AllowUnknownMachine -CertificatePath $certpath -CertificatePassword $certpassword -MediaPassword $bootpassword -MediaMode Dynamic -MediaType CdDvd -Path "$isodir\MMS-BootMedia-x64-$date.iso"
New-CMBootableMedia -BootImage $bootimagex64 -DistributionPoint $dp -ManagementPoint $mp -AllowUacPrompt -AllowUnknownMachine -AllowUnattended -CertificatePath $certpath -CertificatePassword $certpassword -MediaMode Dynamic -MediaType CdDvd -Path "$isodir\MMS-BootMedia-auto5.iso" -Variable @{"SMSTSPreferredAdvertID" = "MMS209DB"} -Force

$prestartpkg = Get-CMPackage -Id MMS01158
$prestartcommand = "cscript.exe WinPE-DNS-ADD.vbs"
New-CMBootableMedia -BootImage $bootimagex64 -DistributionPoint $dp -ManagementPoint $mp -AllowUacPrompt -AllowUnknownMachine -CertificatePath $certpath -CertificatePassword $certpassword -PrestartPackage $prestartpkg -PrestartCommand $prestartcommand -MediaMode Dynamic -MediaType CdDvd -Path "$isodir\boot-$date-test.iso"

Pop-Location

#how to do it the old way
#$dp = "mmsnode1"
#$mps = ("https://mmsnode1.mms.edu","https://mmsnode2.mms.edu")
#$mpstring = ""
#foreach ($mp in $mps) {
#    $mpstring = $mpstring + $mp + "*"
#}
#$mpstring = $mpstring.TrimEnd("*")
#$createmediacmd = "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\i386\CreateMedia.exe"

#& $createmediacmd /K:boot /P:"$sitesrv" /S:"$sitecode" /C:"" /D:"$dp" /X:"SMSTSLocationMPs=$mpstring" /L:"Configuration Manager 2012" /Y:"bootpassword" /R:"$certpath" /W:"certpassword" /U:"True" /J:"False" /Z:"False" /5:"0" /B:"$bootimagex86" /T:"CD" /F:"$isodir\mms-BootMedia-x86-$date.iso" | out-host
#& $createmediacmd /K:boot /P:"$sitesrv" /S:"$sitecode" /C:"" /D:"$dp" /X:"SMSTSLocationMPs=$mpstring" /L:"Configuration Manager 2012" /Y:"bootpassword" /R:"$certpath" /W:"certpassword" /U:"True" /J:"False" /Z:"False" /5:"0" /B:"$bootimagex64" /T:"CD" /F:"$isodir\mms-BootMedia-x64-$date.iso" | out-host
#& $createmediacmd /K:boot /P:"$sitesrv" /S:"$sitecode" /C:"" /D:"$dp" /X:“SMSTSMP=https://mmsnode1.mms.edu" /L:"Configuration Manager 2012" /E:MMS01158 /G:"cscript.exe WinPE-DNS-ADD.vbs" /R:"$certpath" /W:"certpassword" /U:True /J:False /Z:True /5:0 /B:"$bootimagex64" /T:"CD" /F:"$isodir\boot-$date-test.iso" | out-host
