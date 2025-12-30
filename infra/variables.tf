variable "location" {
  type    = string
  default = "France Central"
}
variable "project_name" {
  type    = string
  default = "azure-secureops-studio"
}

variable "subscription_id" {
  type        = string
  description = "the subscription id for the compte"
}
variable "log_analytics_workspace_id" {
  type        = string
  description = "Resource ID of the Log Analytics workspace used for diagnostics"
}
variable "resource_group_id" {
  type        = string
  description = "Resource ID of the resource group"
}