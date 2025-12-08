#############################################
# Remédiation des POLICIES BUILT-IN via Logic App
# - Secure transfer for Storage Accounts
# - Allowed locations
#############################################

# ATTENTION :
# data "azurerm_subscription" "current" est déjà
# déclaré dans un autre fichier (logicapp_owner_tag.tf).
# Ne pas le redéclarer ici.

resource "azurerm_resource_group_template_deployment" "builtin_policy_remediator" {
  name                = "aoss-builtin-policy-remediator-deployment"
  resource_group_name = azurerm_resource_group.rg.name
  deployment_mode     = "Incremental"

  # Paramètres passés au template ARM
  parameters_content = jsonencode({
    logicAppName = {
      value = "aoss-builtin-policy-remediator"
    }

    secureTransferAssignmentId = {
      value = azurerm_subscription_policy_assignment.assign_secure_transfer_storage.id
    }
    allowedLocationsAssignmentId = {
      value = azurerm_subscription_policy_assignment.assign_allowed_locations.id
    }
  })

  # Template ARM de la Logic App (déploiement JSON)
  template_content = jsonencode({
    "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"

    parameters = {
      logicAppName = {
        type         = "string"
        defaultValue = "aoss-builtin-policy-remediator"
      }

      secureTransferAssignmentId = {
        type = "string"
      }
      allowedLocationsAssignmentId = {
        type = "string"
      }
    }

    variables = {}

    resources = [
      {
        type       = "Microsoft.Logic/workflows"
        apiVersion = "2019-05-01"
        name       = "[parameters('logicAppName')]"
        location   = "[resourceGroup().location]"

        # Tag Owner pour satisfaire la custom policy Enforce Owner Tag
        tags = {
          Owner = "NotSet"
        }

        identity = {
          type = "SystemAssigned"
        }

        properties = {
          state      = "Enabled"
          parameters = {}

          definition = {
            "$schema"      = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
            contentVersion = "1.0.0.0"
            parameters     = {}
            outputs        = {}

            # Trigger HTTP (appelé par les tâches de remédiation Azure Policy)
            triggers = {
              manual = {
                type = "Request"
                kind = "Http"
                inputs = {
                  schema = {
                    type = "object"
                    properties = {
                      resourceId = {
                        type = "string"
                      }
                      policyAssignmentId = {
                        type = "string"
                      }
                    }
                    required = [
                      "resourceId",
                      "policyAssignmentId",
                    ]
                  }
                }
              }
            }

            # Actions : Switch sur l'ID d'assignation de policy
            actions = {
              Route_By_Policy = {
                type       = "Switch"
                expression = "@triggerBody()?['policyAssignmentId']"

                cases = {

                  # 1️⃣ Secure transfer for Storage Accounts
                  Secure_Transfer_Storage = {
                    case = "[parameters('secureTransferAssignmentId')]"
                    actions = {
                      Enable_Secure_Transfer = {
                        type = "Http"
                        inputs = {
                          method = "PATCH"
                          uri    = "@concat(triggerBody()?['resourceId'],'?api-version=2023-01-01')"
                          headers = {
                            "Content-Type" = "application/json"
                          }
                          body = {
                            properties = {
                              supportsHttpsTrafficOnly = true
                            }
                          }
                          authentication = {
                            type     = "ManagedServiceIdentity"
                            audience = "https://management.azure.com/"
                          }
                        }
                      }
                    }
                  }

                  # 2️⃣ Allowed locations : on marque la ressource comme non conforme
                  Allowed_Locations = {
                    case = "[parameters('allowedLocationsAssignmentId')]"
                    actions = {
                      Tag_Non_Compliant_Location = {
                        type = "Http"
                        inputs = {
                          method = "PATCH"
                          uri    = "@concat(triggerBody()?['resourceId'],'?api-version=2021-04-01')"
                          headers = {
                            "Content-Type" = "application/json"
                          }
                          body = {
                            tags = {
                              NonCompliantLocation = "true"
                            }
                          }
                          authentication = {
                            type     = "ManagedServiceIdentity"
                            audience = "https://management.azure.com/"
                          }
                        }
                      }
                    }
                  }
                }

                # Case par défaut : pour l’instant rien (tu pourras loguer plus tard)
                default = {
                  actions = {}
                }
              }
            }
          }
        }
      }
    ]

    outputs = {
      logicAppPrincipalId = {
        type  = "string"
        value = "[reference(resourceId('Microsoft.Logic/workflows', parameters('logicAppName')), '2019-05-01', 'Full').identity.principalId]"
      }
    }
  })
}

#############################################
# Rôle Contributor pour la Logic App BUILT-IN
#############################################

resource "azurerm_role_assignment" "builtin_logicapp_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"

  # On récupère l'identity.principalId retourné par le template ARM
  principal_id = jsondecode(
    azurerm_resource_group_template_deployment.builtin_policy_remediator.output_content
  ).logicAppPrincipalId.value
}
