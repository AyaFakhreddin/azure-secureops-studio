data "azurerm_subscription" "current" {}

#Policy DENY : Enforce Owner Tag
resource "azurerm_policy_definition" "enforce_owner_tag" {
  name         = "enforce-owner-tag"
  display_name = "Enforce Owner Tag"
  policy_type  = "Custom"
  mode         = "Indexed"
  description  = "Deny creation or update of resources without the 'Owner' tag."

  policy_rule = jsonencode({
    if = {
      field  = "tags['Owner']"
      exists = "false"
    }
    then = {
      effect = "deny"
    }
  })

  metadata = jsonencode({
    category = "Tags"
    version  = "1.8.0"
  })
}

resource "azurerm_subscription_policy_assignment" "enforce_owner_tag_assignment" {
  name                 = "enforce-owner-tag-assignment"
  display_name         = "Enforce Owner Tag Assignment"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = azurerm_policy_definition.enforce_owner_tag.id
}

resource "azurerm_policy_definition" "modify_owner_tag" {
  name         = "modify-owner-tag"
  display_name = "Auto-add Owner tag when missing"
  policy_type  = "Custom"
  mode         = "Indexed"
  description  = "Adds the Owner tag with a default value when it is missing."

  # Ici on met TOUTE la règle directement, sans fichier externe,
  # et SURTOUT sans parameters().
  policy_rule = jsonencode({
    if = {
      field  = "tags['Owner']"
      exists = "false"
    }
    then = {
      effect = "modify"
      details = {
        operations = [
          {
            operation = "add"
            field     = "tags['Owner']"
            value     = "AutoAssigned"
          }
        ]
        roleDefinitionIds = [
          "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
        ]
      }
    }
  })

  metadata = jsonencode({
    category = "Tags"
    version  = "1.0.0"
  })
}
resource "azurerm_subscription_policy_assignment" "modify_owner_tag_assignment" {
  name                 = "modify-owner-tag-assignment"
  display_name         = "Modify Owner Tag Assignment"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = azurerm_policy_definition.modify_owner_tag.id
}
