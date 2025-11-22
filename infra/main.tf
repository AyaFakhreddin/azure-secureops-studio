resource "azurerm_resource_group" "rg" {
  name     = "aoss-dev-rg-secops"
  location = var.location

  tags = {
    project = "azure-secureops-studio"
    env     = "dev"
  }
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "aoss-law-dev"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku               = "PerGB2018"
  retention_in_days = 30
}

resource "azurerm_storage_account" "st" {
  name                     = "aossdevstg2025"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.st.name
  container_access_type = "private"
}

#test