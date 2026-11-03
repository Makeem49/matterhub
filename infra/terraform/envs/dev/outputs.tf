output "platform" {
  description = "All platform outputs; read by pipelines with `terraform output -json platform`."
  value       = module.platform
  sensitive   = true
}
