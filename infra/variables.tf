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
variable "secops_rg_name" {
  description = "Resource Group used by AzureSecureOps"
  type        = string
  default     = "aoss-dev-rg-secops"
}
variable "accesslens_law_name" {
  description = "Log Analytics Workspace name for AccessLens Lite"
  type        = string
}

variable "accesslens_law_retention" {
  description = "Retention period for Log Analytics Workspace"
  type        = number
  default     = 30
}
variable "accesslens_diag_name" {
  type    = string
  default = "accesslens-activity-logs"
}