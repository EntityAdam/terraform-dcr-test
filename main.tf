terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "dcr_rg" {
  name     = "rg-dcr-test"
  location = "East US"
}

# Log Analytics Workspace (for Windows events)
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-dcr-test"
  location            = azurerm_resource_group.dcr_rg.location
  resource_group_name = azurerm_resource_group.dcr_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Event Hubs Namespace
resource "azurerm_eventhub_namespace" "ehn" {
  name                = "ehn-dcr-test"
  location            = azurerm_resource_group.dcr_rg.location
  resource_group_name = azurerm_resource_group.dcr_rg.name
  sku                 = "Standard"
  capacity            = 1
}

# Event Hub
resource "azurerm_eventhub" "eh" {
  name                = "eh-dcr-test"
  namespace_name      = azurerm_eventhub_namespace.ehn.name
  resource_group_name = azurerm_resource_group.dcr_rg.name
  partition_count     = 2
  message_retention   = 1
}

# Data Collection Endpoint
resource "azurerm_monitor_data_collection_endpoint" "dce" {
  name                = "dce-dcr-test"
  resource_group_name = azurerm_resource_group.dcr_rg.name
  location            = azurerm_resource_group.dcr_rg.location
  kind                = "Linux"
}

# Data Collection Rule - Linux (Syslog to Event Hub Direct)
resource "azurerm_monitor_data_collection_rule" "dcr_linux" {
  name                = "dcr-linux-test"
  resource_group_name = azurerm_resource_group.dcr_rg.name
  location            = azurerm_resource_group.dcr_rg.location
  kind                = "AgentDirectToStore"

  destinations {
    event_hub_direct {
      event_hub_id = azurerm_eventhub.eh.id
      name         = "destination-eventhub"
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["destination-eventhub"]
  }

  data_sources {
    syslog {
      facility_names = ["*"]
      log_levels     = ["*"]
      name           = "datasource-syslog"
    }
  }

  description = "Data Collection Rule for Linux syslog to Event Hub"
}

# Data Collection Rule - Windows (Events to Log Analytics)
resource "azurerm_monitor_data_collection_rule" "dcr_windows" {
  name                        = "dcr-windows-test"
  resource_group_name         = azurerm_resource_group.dcr_rg.name
  location                    = azurerm_resource_group.dcr_rg.location
  kind                        = "Windows"
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
      name                  = "destination-log"
    }
  }

  data_flow {
    streams      = ["Microsoft-Event"]
    destinations = ["destination-log"]
  }

  data_sources {
    windows_event_log {
      streams        = ["Microsoft-Event"]
      x_path_queries = ["Application!*[System[(Level=1 or Level=2 or Level=3)]]", "Security!*[System[(band(Keywords,13510798882111488))]]", "System!*[System[(Level=1 or Level=2 or Level=3)]]"]
      name           = "datasource-wineventlog"
    }
  }

  description = "Data Collection Rule for Windows events to Log Analytics"
}

# Diagnostic Settings to stream Log Analytics to Event Hub
resource "azurerm_monitor_diagnostic_setting" "law_to_eventhub" {
  name                       = "law-to-eventhub"
  target_resource_id         = azurerm_log_analytics_workspace.law.id
  eventhub_authorization_rule_id = azurerm_eventhub_namespace_authorization_rule.law_send.id
  eventhub_name              = azurerm_eventhub.eh.name

  enabled_log {
    category = "Audit"
  }

  metric {
    category = "AllMetrics"
  }
}

# Event Hub Authorization Rule for Log Analytics
resource "azurerm_eventhub_namespace_authorization_rule" "law_send" {
  name                = "law-send-rule"
  namespace_name      = azurerm_eventhub_namespace.ehn.name
  resource_group_name = azurerm_resource_group.dcr_rg.name

  listen = false
  send   = true
  manage = false
}
