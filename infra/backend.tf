terraform {
  backend "azurerm" {
    resource_group_name  = "aoss-dev-rg-secops"
    storage_account_name = "aossdevstg2025"
    container_name       = "tfstate"
    key                  = "secureops/terraform.tfstate"
  }
}
E