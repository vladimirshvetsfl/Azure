### Resource Group ###
resource "azurerm_resource_group" "backup_rg" {
  name     = "backup-${var.location}"
  location = var.location
}


### Resource Guard  ###
resource "azurerm_data_protection_resource_guard" "resource_guard" {
  name                = "resource-guard-${var.location}"
  resource_group_name = azurerm_resource_group.backup_rg.name
  location            = azurerm_resource_group.backup_rg.location
  vault_critical_operation_exclusion_list = [
    "Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems/delete",
    "Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems/write",
    "Microsoft.RecoveryServices/vaults/backupSecurityPIN/action"
  ]
}

### Azure Recovery Service Vaults ###

resource "azurerm_recovery_services_vault" "rsv_geo" {
  name                = "rsv-${var.location}-geo"
  resource_group_name = azurerm_resource_group.backup_rg.name
  location            = azurerm_resource_group.backup_rg.location
  sku                 = "Standard"
  immutability        = "Disabled"
  storage_mode_type   = "GeoRedundant"

  cross_region_restore_enabled = true
  soft_delete_enabled          = true
}

resource "azurerm_recovery_services_vault_resource_guard_association" "resource_guard_association" {
  vault_id          = azurerm_recovery_services_vault.rsv_geo.id
  resource_guard_id = azurerm_data_protection_resource_guard.resource_guard.id
}

/* resource "azurerm_monitor_diagnostic_setting" "rsv_diag" { #! Enable for diagnostic settings
  name                       = "diag"
  target_resource_id         = azurerm_recovery_services_vault.rsv_geo.id
  eventhub_authorization_rule_id = ""
  eventhub_name = ""
  enabled_log {
    category_group = "allLogs"
  }

} */

### Backup Policy ###

resource "azurerm_backup_policy_vm" "backup_policy_m3" {
  name                = "bkpol-m3"
  resource_group_name = azurerm_resource_group.backup_rg.name
  recovery_vault_name = azurerm_recovery_services_vault.rsv_geo.name
  policy_type         = "V2"


  timezone = "UTC"

  backup {
    frequency = "Daily"
    time      = "00:30"
  }

  retention_daily {
    count = 90
  }

  retention_weekly {
    count    = 52
    weekdays = ["Saturday"]
  }

  retention_monthly {
    count    = 36
    weekdays = ["Saturday"]
    weeks    = ["First"]
  }

}

resource "azurerm_backup_policy_vm" "backup_policy_m2" {
  name                = "bkpol-m2"
  resource_group_name = azurerm_resource_group.backup_rg.name
  recovery_vault_name = azurerm_recovery_services_vault.rsv_geo.name
  policy_type         = "V2"

  timezone = "UTC"

  backup {
    frequency = "Daily"
    time      = "23:00"
  }

  retention_daily {
    count = 60
  }
}

resource "azurerm_backup_policy_vm" "backup_policy_m1" {
  name                = "bkpol-m1"
  resource_group_name = azurerm_resource_group.backup_rg.name
  recovery_vault_name = azurerm_recovery_services_vault.rsv_geo.name
  policy_type         = "V2"

  timezone = "UTC"

  backup {
    frequency = "Daily"
    time      = "01:00"
  }

  retention_daily {
    count = 30
  }
}



### Azure Policy Assignments ###

resource "azurerm_user_assigned_identity" "backup_remediation_uami" {
  name                = "backup-remediation"
  location            = azurerm_resource_group.backup_rg.location
  resource_group_name = azurerm_resource_group.backup_rg.name
}

resource "azurerm_role_assignment" "policy_rbac_vm_contributor" {
  scope                = var.subscription_id
  principal_id         = azurerm_user_assigned_identity.backup_remediation_uami.principal_id
  role_definition_name = "Virtual Machine Contributor"
}

resource "azurerm_role_assignment" "policy_rbac_backup_contributor" {
  scope                = var.subscription_id
  principal_id         = azurerm_user_assigned_identity.backup_remediation_uami.principal_id
  role_definition_name = "Backup Contributor"
}

resource "azurerm_subscription_policy_assignment" "azure_policy_assignment_m3" {
  name                 = "SnapshotRetentionM3"
  display_name         = "SnapshotRetentionM3"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/345fa903-145c-4fe1-8bcd-93ec2adccde8"
  subscription_id      = var.subscription_id
  location             = azurerm_recovery_services_vault.rsv_geo.location

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.backup_remediation_uami.id]
  }

  parameters = <<PARAMETERS
  {
    "vaultLocation" : {
      "value" : "${azurerm_recovery_services_vault.rsv_geo.location}"
    },
    "inclusionTagName" : {
      "value" : "${var.inclusion_tag_name}"
    },
    "inclusionTagValue" : {
      "value" : [
        "${var.inclusion_tag_value}"
      ]
    },
    "backupPolicyId" : {
      "value" : "${azurerm_backup_policy_vm.backup_policy_m3.id}"
    }
  }
  PARAMETERS

}

resource "azurerm_subscription_policy_remediation" "remediation" {
  name                    = "pol-remediation"
  policy_assignment_id    = "${var.subscription_id}/providers/Microsoft.Authorization/policyAssignments/${azurerm_subscription_policy_assignment.azure_policy_assignment_m3.name}"
  subscription_id         = var.subscription_id
  resource_discovery_mode = "ReEvaluateCompliance"
}
