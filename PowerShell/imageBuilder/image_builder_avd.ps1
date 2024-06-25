<# DISCLAIMER
This Sample Code is provided for the purpose of illustration only
and is not intended to be used in a production environment.  THIS
SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED AS IS
WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF
MERCHANTABILITY ANDOR FITNESS FOR A PARTICULAR PURPOSE.  We
grant You a nonexclusive, royalty-free right to use and modify
the Sample Code and to reproduce and distribute the object code
form of the Sample Code, provided that You agree (i) to not use
Our name, logo, or trademarks to market Your software product in
which the Sample Code is embedded; (ii) to include a valid
copyright notice on Your software product in which the Sample

Code is embedded; and (iii) to indemnify, hold harmless, and
defend Us and Our suppliers from and against any claims or
lawsuits, including attorneys’ fees, that arise or result from
the use or distribution of the Sample Code.
Please note None of the conditions outlined in the disclaimer
above will supersede the terms and conditions contained within
the Premier Customer Services Description.
#>

#Random Gen

$random = Get-Random -Minimum 1000 -Maximum 10000

# Destination image resource group name
$imageResourceGroup = "avd-img-bldr-rg-" + $random

# Azure region
$location = "EastUS2"

# Name of the image to be created
$imageTemplateName = "avd-win11-23h2-office"

# Distribution properties of the managed image upon completion
$runOutputName = "avd-win11-23h2-office-output"

# Your Azure Subscription ID
$subscriptionID = (Get-AzContext).Subscription.Id

#create resource groups
New-AzResourceGroup -Name $imageResourceGroup -Location $location

#Create variables for the role definition and identity names. These values must be unique.
$imageRoleDefName = "Azure Image Builder " + $random
$identityName = "avd-imgbldr-" + $random

#Create user identity
New-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName -Location $location

#Store the identity resource and principal IDs in variables.
$identityNameResourceId = (Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName).Id
$identityNamePrincipalId = (Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName).PrincipalId


#Download the JSON configuration file, and then modify it based on the settings that are defined in this article.
$myRoleImageCreationUrl = "https://raw.githubusercontent.com/azure/azvmimagebuilder/master/solutions/12_Creating_AIB_Security_Roles/aibRoleImageCreation.json"
$myRoleImageCreationPath = "c:\temp\myRoleImageCreation.json"

Invoke-WebRequest -Uri $myRoleImageCreationUrl -OutFile $myRoleImageCreationPath -UseBasicParsing

$Content = Get-Content -Path $myRoleImageCreationPath -Raw
$Content = $Content -replace "<subscriptionID>", $subscriptionID
$Content = $Content -replace "<rgName>", $imageResourceGroup
$Content = $Content -replace "Azure Image Builder Service Image Creation Role", $imageRoleDefName
$Content | Out-File -FilePath $myRoleImageCreationPath -Force

#Create the role definition.
New-AzRoleDefinition -InputFile $myRoleImageCreationPath

#Grant the role definition to the VM Image Builder service principal
$RoleAssignParams = @{
    ObjectId           = $identityNamePrincipalId
    RoleDefinitionName = $imageRoleDefName
    Scope              = "/subscriptions/$subscriptionID/resourceGroups/$imageResourceGroup"
}
New-AzRoleAssignment @RoleAssignParams

# Create gallery
$myGalleryName = "avdgal01"
$imageDefName = "avd-win11-23h2-office"

New-AzGallery -GalleryName $myGalleryName -ResourceGroupName $imageResourceGroup -Location $location

#Create a gallery definition.
$GalleryParams = @{
    GalleryName       = $myGalleryName
    ResourceGroupName = $imageResourceGroup
    Location          = $location
    Name              = $imageDefName
    OsState           = "generalized"
    OsType            = "Windows"
    Publisher         = "MicrosoftWindowsDesktop"
    Offer             = "office-365"
    Sku               = "win11-23h2-avd-m365"
    HyperVGeneration  = "V2"
}

$SecurityType = @{Name = "SecurityType"; Value = "TrustedlaunchSupported" }
New-AzGalleryImageDefinition @GalleryParams -Feature $SecurityType

#Create a VM Image Builder source object.
$SrcObjParams = @{
    PlatformImageSource = $true
    Publisher           = "MicrosoftWindowsDesktop"
    Offer               = "office-365"
    Sku                 = "win11-23h2-avd-m365"
    Version             = "latest"
}
$srcPlatform = New-AzImageBuilderTemplateSourceObject @SrcObjParams

#Create a VM Image Builder distributor object.
$disObjParams = @{
    SharedImageDistributor = $true
    ArtifactTag            = @{tag = "dis-share" }
    GalleryImageId         = "/subscriptions/$subscriptionID/resourceGroups/$imageResourceGroup/providers/Microsoft.Compute/galleries/$myGalleryName/images/$imageDefName"
    ReplicationRegion      = $location
    RunOutputName          = $runOutputName
    ExcludeFromLatest      = $false
}
$disSharedImg = New-AzImageBuilderTemplateDistributorObject @disObjParams

$ImgCustomParams01 = @{
    PowerShellCustomizer = $true
    Name                 = "optimizeAVD"
    RunElevated          = $true
    runAsSystem          = $true
    ScriptUri            = "https://raw.githubusercontent.com/danielsollondon/azvmimagebuilder/master/solutions/14_Building_Images_WVD/1_Optimize_OS_for_WVD.ps1"
}
$Customizer01 = New-AzImageBuilderTemplateCustomizerObject @ImgCustomParams01

#Create a VM Image Builder template.
$ImgTemplateParams = @{
    ImageTemplateName      = $imageTemplateName
    ResourceGroupName      = $imageResourceGroup
    Source                 = $srcPlatform
    Distribute             = $disSharedImg
    Customize              = $Customizer01
    Location               = $location
    UserAssignedIdentityId = $identityNameResourceId
}
New-AzImageBuilderTemplate @ImgTemplateParams

#Start image build
$imageBuilderJob = Start-AzImageBuilderTemplate -ResourceGroupName $imageResourceGroup -Name $imageTemplateName -AsJob

#Start image build
Start-AzImageBuilderTemplate -ResourceGroupName $imageResourceGroup -Name $imageTemplateName -NoWait
