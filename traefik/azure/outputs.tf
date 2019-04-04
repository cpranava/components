output "ingress_fqdn" {
  value = "${var.url_prefix}.${var.domain_name}"
}

output "sso_ingress_fqdn" {
  value = "${var.sso_url_prefix}.${var.domain_name}"
}

output "load_balancer" {
  value = "${data.kubernetes_service.traefik.load_balancer_ingress.0.hostname}"
}