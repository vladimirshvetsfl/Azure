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

# Destination image resource group name
$imageResourceGroup = 'img-bldr-rg'
$strResourceGroup = "shared-resources"
$scriptStorageAcc = "imgbldr"

# Script container
$scriptStorageAccContainer = "script"

# Script URL
$scriptUrl = "https://$scriptStorageAcc.blob.core.windows.net/$scriptStorageAccContainer/script.ps1"

# Azure region
$location = 'EastUS'

# Name of the image to be created
$imageTemplateName = 'windows2022'

# Distribution properties of the managed image upon completion
$runOutputName = 'myDistResults'

# Your Azure Subscription ID
$subscriptionID = (Get-AzContext).Subscription.Id

#create resource group
New-AzResourceGroup -Name $imageResourceGroup -Location $location

#Create variables for the role definition and identity names. These values must be unique.
#[int]$timeInt = $(Get-Date -UFormat '%s')
$imageRoleDefName = "Azure Image Builder"
$identityName = "imgbldr"

#Create user identity
New-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName -Location $location

#Store the identity resource and principal IDs in variables.
$identityNameResourceId = (Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName).Id
$identityNamePrincipalId = (Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName).PrincipalId

#Create Storage Account and container
New-AzStorageAccount -Location $location -ResourceGroupName $strResourceGroup -Name $scriptStorageAcc -SkuName Standard_LRS -Kind BlobStorage -AccessTier Hot

$strAccountCTX = (Get-AzStorageAccount -ResourceGroupName $strResourceGroup -Name $scriptStorageAcc).Context
New-AzStorageContainer -Context $strAccountCTX -Name $scriptStorageAccContainer

Start-AzStorageBlobCopy -DestContainer $scriptStorageAccContainer -DestContext $strAccountCTX -AbsoluteUri https://github.com/vladimirshvetsfl/public/blob/main/script.ps1 -DestBlob script.ps1

New-AzRoleAssignment -RoleDefinitionName "Storage Blob Data Reader" -ObjectId $identityNamePrincipalId -Scope "/subscriptions/$subscriptionID/resourceGroups/$strResourceGroup/providers/Microsoft.Storage/storageAccounts/$scriptStorageAcc/blobServices/default/containers/$scriptStorageAccContainer"

#Download the JSON configuration file, and then modify it based on the settings that are defined in this article.
$myRoleImageCreationUrl = 'https://raw.githubusercontent.com/azure/azvmimagebuilder/master/solutions/12_Creating_AIB_Security_Roles/aibRoleImageCreation.json'
$myRoleImageCreationPath = "c:\temp\myRoleImageCreation.json"

Invoke-WebRequest -Uri $myRoleImageCreationUrl -OutFile $myRoleImageCreationPath -UseBasicParsing

$Content = Get-Content -Path $myRoleImageCreationPath -Raw
$Content = $Content -replace '<subscriptionID>', $subscriptionID
$Content = $Content -replace '<rgName>', $imageResourceGroup
$Content = $Content -replace 'Azure Image Builder Service Image Creation Role', $imageRoleDefName
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
$myGalleryName = 'images'
$imageDefName = 'winImage'

New-AzGallery -GalleryName $myGalleryName -ResourceGroupName $imageResourceGroup -Location $location

#Create a gallery definition.
$GalleryParams = @{
    GalleryName       = $myGalleryName
    ResourceGroupName = $imageResourceGroup
    Location          = $location
    Name              = $imageDefName
    OsState           = 'generalized'
    OsType            = 'Windows'
    Publisher         = 'ShvetsCloud'
    Offer             = 'Windows'
    Sku               = 'Win2022'
    HyperVGeneration  = "V2"
}
New-AzGalleryImageDefinition @GalleryParams

#Create a VM Image Builder source object.
$SrcObjParams = @{
    PlatformImageSource = $true
    Publisher           = 'MicrosoftWindowsServer'
    Offer               = 'WindowsServer'
    Sku                 = '2022-datacenter-g2'
    Version             = 'latest'
}
$srcPlatform = New-AzImageBuilderTemplateSourceObject @SrcObjParams

#Create a VM Image Builder distributor object.
$disObjParams = @{
    SharedImageDistributor = $true
    ArtifactTag            = @{tag = 'dis-share' }
    GalleryImageId         = "/subscriptions/$subscriptionID/resourceGroups/$imageResourceGroup/providers/Microsoft.Compute/galleries/$myGalleryName/images/$imageDefName"
    ReplicationRegion      = $location
    RunOutputName          = $runOutputName
    ExcludeFromLatest      = $false
}
$disSharedImg = New-AzImageBuilderTemplateDistributorObject @disObjParams

<##Create a VM Image Builder customization objects
 $ImgCustomParams01 = @{
    PowerShellCustomizer = $true
    Name                 = 'settingUpMgmtAgtPath'
    RunElevated          = $false
    Inline               = @("mkdir c:\\buildActions", "mkdir c:\\buildArtifacts", "echo Azure-Image-Builder-Was-Here  > c:\\buildActions\\buildActionsOutput.txt")
}
$Customizer01 = New-AzImageBuilderTemplateCustomizerObject @ImgCustomParams01

$ImgCustomParams02 = @{
    FileCustomizer = $true
    Name           = 'downloadBuildArtifacts'
    Destination    = 'c:\\buildArtifacts\\index.html'
    SourceUri      = 'https://raw.githubusercontent.com/azure/azvmimagebuilder/master/quickquickstarts/exampleArtifacts/buildArtifacts/index.html'
}
$Customizer02 = New-AzImageBuilderTemplateCustomizerObject @ImgCustomParams02
#>

$ImgCustomParams01 = @{
    PowerShellCustomizer = $true
    Name                 = 'script'
    RunElevated          = $false
    ScriptUri            = $scriptUrl
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
Start-AzImageBuilderTemplate -ResourceGroupName $imageResourceGroup -Name $imageTemplateName