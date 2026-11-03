output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "aks_subnet_id" {
  value = azurerm_subnet.aks.id
}

output "postgres_subnet_id" {
  value = azurerm_subnet.postgres.id
}

output "private_endpoints_subnet_id" {
  value = azurerm_subnet.private_endpoints.id
}

output "postgres_subnet_cidr" {
  value = var.subnet_cidrs.postgres
}

# Exposed through the VNet link so dependants wait until the zone is linked.
output "private_dns_zone_ids" {
  description = "Map of zone key (postgres, keyvault, acr) to private DNS zone ID."
  value       = { for k, link in azurerm_private_dns_zone_virtual_network_link.this : k => link.private_dns_zone_id }
}
