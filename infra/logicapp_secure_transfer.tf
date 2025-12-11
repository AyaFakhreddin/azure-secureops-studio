########################################
# Logic App - Secure Transfer Remediation
########################################

# ⚠️ Prérequis :
# - azurerm_resource_group.rg existe déjà (RG = aoss-dev-rg-secops)
# - data.azurerm_subscription.current déjà défini (cf. fichier précédent)

resource "azurerm_resource_group_template_deployment" "la_secure_transfer" {
  name                = "la-secure-transfer-remediation-deployment"
  resource_group_name = azurerm_resource_group.rg.name
  deployment_mode     = "Incremental"

  template_content = jsonencode({
    "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"

    parameters = {}

    variables = {
      logicAppName = "la-secure-transfer-remediation"
    }

    resources = [
      {
        type       = "Microsoft.Logic/workflows"
        apiVersion = "2019-05-01"
        name       = "[variables('logicAppName')]"
        location   = "[resourceGroup().location]"

        // ⚠️ IMPORTANT : pour passer la policy Enforce Owner Tag
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

            triggers = {
              manual = {
                type = "Request"
                kind = "Http"
                inputs = {
                  schema = {
                    type       = "object"
                    properties = {
                      resourceId = {
                        type = "string"
                      }
                    }
                    required = ["resourceId"]
                  }
                }
              }
            }

            actions = {
              patch_secure_transfer = {
                type = "Http"
                inputs = {
                  method = "PATCH"
                  uri    = "@{concat('https://management.azure.com', triggerBody()?['resourceId'], '?api-version=2023-01-01')}"
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
        }
      }
    ]

    outputs = {
      logicAppPrincipalId = {
        type  = "string"
        value = "[reference(resourceId('Microsoft.Logic/workflows', variables('logicAppName')), '2019-05-01', 'Full').identity.principalId]"
      }
    }
  })
}


# Donner le rôle Contributor à l'identité managée de la Logic App
resource "azurerm_role_assignment" "la_secure_transfer_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"

  principal_id = jsondecode(
    azurerm_resource_group_template_deployment.la_secure_transfer.output_content
  ).logicAppPrincipalId.value
}
