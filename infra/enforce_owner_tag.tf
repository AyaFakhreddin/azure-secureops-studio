# Attention : ce data doit exister UNE SEULE FOIS dans tout ton projet.
# Si tu l'as déjà dans un autre fichier (par ex. policies_builtin.tf), ne le duplique pas.
data "azurerm_subscription" "current" {}

# =========================================================
# 1 POLICY DENY : Enforce Owner Tag (bloque les nouveaux)
# =========================================================
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
    version  = "1.0.0"
  })
}

resource "azurerm_subscription_policy_assignment" "enforce_owner_tag_assignment" {
  name                 = "enforce-owner-tag-assignment"
  display_name         = "Enforce Owner Tag Assignment"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = azurerm_policy_definition.enforce_owner_tag.id
}
