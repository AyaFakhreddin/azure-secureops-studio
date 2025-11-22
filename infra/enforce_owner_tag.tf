resource "azurerm_policy_definition" "enforce_owner_tag" {
  name         = "enforce-owner-tag"
  display_name = "Enforce Owner Tag"
  policy_type  = "Custom"
  mode         = "Indexed"
  description  = "Deny creation or update of resources without the 'Owner' tag."

  // 👉 Ici on met SEULEMENT la règle (policyRule)
  policy_rule = jsonencode({
    if = {
      field  = "tags['Owner']"
      exists = "false"
    }
    then = {
      effect = "deny"
    }
  })

  // 👉 Metadata au bon format JSON aussi
  metadata = jsonencode({
    category = "Tags"
    version  = "1.0.0"
  })
}

data "azurerm_subscription" "current" {}

resource "azurerm_policy_assignment" "enforce_owner_tag_assignment" {
  name                 = "enforce-owner-tag-assignment"
  display_name         = "Enforce Owner Tag Assignment"
  scope                = data.azurerm_subscription.current.id
  policy_definition_id = azurerm_policy_definition.enforce_owner_tag.id
  enforcement_mode     = "Default"
}
