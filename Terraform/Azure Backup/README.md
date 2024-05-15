# Overview
This sample terraform code deploys the following Azure resources and configurations:

- azurerm_resource_group
- azurerm_data_protection_resource_guard
- azurerm_recovery_services_vault
- azurerm_recovery_services_vault_resource_guard_association
- azurerm_backup_policy_vm
- azurerm_user_assigned_identity
- azurerm_subscription_policy_assignment
- azurerm_subscription_policy_remediation
- azapi_update_resource

## Azure Recovery Services Vault
The code creates an Azure Recovery Services Vault.  The vault contains backup policies that are associated with the protected resources.

## Azure Backup Policies
The code creates several sample Azure Backup policies, each with a different retention period for the backup data.

Tiering is enabled via `azapi` provider, utilizing the `azapi_update_resource` resource.

## Resource Guard
The code enables Resource Guard for the Azure Recovery Services Vault.

## Azure Policy Assignment
The code creates an Azure Policy assignment that applies specific backup policies to the virtual machines based on their tags. The policy assignment uses the built-in policy definition `Configure backup on virtual machines with a given tag to an existing recovery services vault in the same location`.

The policy assignment then assigns the corresponding backup policy to the virtual machines based on the tag value.

## Azure Policy Remediation
The code also creates an Azure Policy remediation task that automatically deploys the backup policy to the non-compliant virtual machines. The remediation task uses a User Assigned Managed Identity (UAMI) to perform the remediation actions. The UAMI is granted the necessary permissions to the Azure Recovery Services Vault and the virtual machines.


