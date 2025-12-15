resource "azurerm_resource_group_template_deployment" "la_owner_tag" {
  name                = "la-owner-tag-remediation-deployment"
  resource_group_name = azurerm_resource_group.rg.name
  deployment_mode     = "Incremental"

  depends_on = [
    azurerm_subscription_policy_assignment.assign_allowed_locations
  ]

  template_content = <<TEMPLATE
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {},
  "variables": {
    "logicAppName": "la-owner-tag-remediation"
  },
  "resources": [
    {
      "type": "Microsoft.Logic/workflows",
      "apiVersion": "2019-05-01",
      "name": "[variables('logicAppName')]",
      "location": "[resourceGroup().location]",
      "tags": {
        "Owner": "NotSet"
      },
      "identity": {
        "type": "SystemAssigned"
      },
      "properties": {
        "state": "Enabled",
        "definition": {
          "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
          "contentVersion": "1.0.0.0",
          "parameters": {},
          "triggers": {
            "manual": {
              "type": "Request",
              "kind": "Http",
              "inputs": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "resourceId": {
                      "type": "string"
                    }
                  },
                  "required": [
                    "resourceId"
                  ]
                }
              }
            }
          },
          "actions": {
            "Initialize_apiVersion": {
              "type": "InitializeVariable",
              "inputs": {
                "variables": [
                  {
                    "name": "apiVersion",
                    "type": "string",
                    "value": "2021-04-01"
                  }
                ]
              }
            },

            "Set_apiVersion_workspace": {
              "type": "If",
              "expression": "@{contains(toLower(triggerBody()?['resourceId']), '/providers/microsoft.operationalinsights/workspaces/')}",
              "actions": {
                "SetVariable_workspace": {
                  "type": "SetVariable",
                  "inputs": {
                    "name": "apiVersion",
                    "value": "2022-10-01"
                  }
                }
              },
              "else": {
                "actions": {}
              },
              "runAfter": {
                "Initialize_apiVersion": [
                  "Succeeded"
                ]
              }
            },

            "Set_apiVersion_solution": {
              "type": "If",
              "expression": "@{contains(toLower(triggerBody()?['resourceId']), '/providers/microsoft.operationsmanagement/solutions/')}",
              "actions": {
                "SetVariable_solution": {
                  "type": "SetVariable",
                  "inputs": {
                    "name": "apiVersion",
                    "value": "2015-11-01-preview"
                  }
                }
              },
              "else": {
                "actions": {}
              },
              "runAfter": {
                "Set_apiVersion_workspace": [
                  "Succeeded"
                ]
              }
            },

            "patch_owner_tag": {
              "type": "Http",
              "runAfter": {
                "Set_apiVersion_solution": [
                  "Succeeded"
                ]
              },
              "inputs": {
                "method": "PATCH",
                "uri": "@{concat('https://management.azure.com', triggerBody()?['resourceId'], '?api-version=', variables('apiVersion'))}",
                "headers": {
                  "Content-Type": "application/json"
                },
                "body": {
                  "tags": {
                    "Owner": "AutoAssigned"
                  }
                },
                "authentication": {
                  "type": "ManagedServiceIdentity",
                  "audience": "https://management.azure.com/"
                }
              }
            }
          },
          "outputs": {}
        },
        "parameters": {}
      }
    }
  ],
  "outputs": {
    "logicAppPrincipalId": {
      "type": "string",
      "value": "[reference(resourceId('Microsoft.Logic/workflows', variables('logicAppName')), '2019-05-01', 'Full').identity.principalId]"
    }
  }
}
TEMPLATE
}

# Donne le rôle Contributor à la Logic App sur la subscription
resource "azurerm_role_assignment" "la_owner_tag_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"

  # On récupère le principalId depuis l'output de l'ARM template
  principal_id = jsondecode(
    azurerm_resource_group_template_deployment.la_owner_tag.output_content
  ).logicAppPrincipalId.value
}



