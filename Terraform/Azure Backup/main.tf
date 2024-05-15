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

/* resource "azurerm_monitor_diagnostic_setting" "rsv_diag" { #* Enable for diagnostic settings
  name                       = "diag"
  target_resource_id         = azurerm_recovery_services_vault.rsv_geo.id
  eventhub_authorization_rule_id = ""
  eventhub_name = ""
  enabled_log {
    category_group = "allLogs"
  }

} */

### Backup Policies ###

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

/* #* Powershell command to enable tiering
Set-AzRecoveryServicesBackupProtectionPolicy -VaultId $VAULT_ID -Policy $POLICY -MoveToArchiveTier $true -TieringMode TierAllEligible -TierAfterDuration 3 -TierAfterDurationType Months
*/

resource "azapi_update_resource" "tiering_policies" {
  type        = "Microsoft.RecoveryServices/vaults/backupPolicies@2023-02-01"
  resource_id = azurerm_backup_policy_vm.backup_policy_m3.id

  body = jsonencode(
    {
      "properties" : {
        "backupManagementType" : "AzureIaasVM",
        "instantRPDetails" : {},
        "schedulePolicy" : {
          "schedulePolicyType" : "SimpleSchedulePolicyV2",
          "scheduleRunFrequency" : "Daily",
          "dailySchedule" : {
            "scheduleRunTimes" : [
              "2024-05-14T00:30:00Z"
            ]
          }
        },
        "retentionPolicy" : {
          "retentionPolicyType" : "LongTermRetentionPolicy",
          "dailySchedule" : {
            "retentionTimes" : [
              "2024-05-14T00:30:00Z"
            ],
            "retentionDuration" : {
              "count" : 90,
              "durationType" : "Days"
            }
          },
          "weeklySchedule" : {
            "daysOfTheWeek" : [
              "Saturday"
            ],
            "retentionTimes" : [
              "2024-05-14T00:30:00Z"
            ],
            "retentionDuration" : {
              "count" : 52,
              "durationType" : "Weeks"
            }
          },
          "monthlySchedule" : {
            "retentionScheduleFormatType" : "Weekly",
            "retentionScheduleWeekly" : {
              "daysOfTheWeek" : [
                "Saturday"
              ],
              "weeksOfTheMonth" : [
                "First"
              ]
            },
            "retentionTimes" : [
              "2024-05-14T00:30:00Z"
            ],
            "retentionDuration" : {
              "count" : 36,
              "durationType" : "Months"
            }
          }
        },
        "tieringPolicy" : {
          "ArchivedRP" : {
            "tieringMode" : "TierAfter",
            "duration" : 3,
            "durationType" : "Months"
          }
        },
        "instantRpRetentionRangeInDays" : 7,
        "timeZone" : "UTC",
        "policyType" : "V2"
      }
    }
  )
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
  scope                = "/subscriptions/${var.subscription_id}"
  principal_id         = azurerm_user_assigned_identity.backup_remediation_uami.principal_id
  role_definition_name = "Virtual Machine Contributor"
}

resource "azurerm_role_assignment" "policy_rbac_backup_contributor" {
  scope                = "/subscriptions/${var.subscription_id}"
  principal_id         = azurerm_user_assigned_identity.backup_remediation_uami.principal_id
  role_definition_name = "Backup Contributor"
}

resource "azurerm_subscription_policy_assignment" "azure_policy_assignment_m3" {
  name                 = "SnapshotRetentionM3"
  display_name         = "SnapshotRetentionM3"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/345fa903-145c-4fe1-8bcd-93ec2adccde8"
  subscription_id      = "/subscriptions/${var.subscription_id}"
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
  policy_assignment_id    = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/policyAssignments/${azurerm_subscription_policy_assignment.azure_policy_assignment_m3.name}"
  subscription_id         = "/subscriptions/${var.subscription_id}"
  resource_discovery_mode = "ReEvaluateCompliance"
}
