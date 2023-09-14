# Bucket to store website
resource "google_storage_bucket" "website" {
    name      = var.gcp_bucket_name
    location  = "EU" 
}

# Make new object publicly accessible
resource "google_storage_object_access_control" "public_rule" {
    bucket = google_storage_bucket.website.name
    object = google_storage_bucket_object.static_site_src.name
    role   = "READER"
    entity = "allUsers"
}

# Upload the html file to the bucket
resource "google_storage_bucket_object" "static_site_src" {
    name    = "index.html"
    source  = "../website/index.html"
    bucket  = google_storage_bucket.website.name
}

# Reserve a external static IP address
resource "google_compute_global_address" "website_ip" {
    name = "website-lb-ip"   
}

# Get the managed DNS zone
data "google_dns_managed_zone" "dns_zone" {
  name = "terraform-gcp"
}

# Add IP to the DNS
resource "google_dns_record_set" "website" {
    name = "website.${data.google_dns_managed_zone.dns_zone.dns_name}"
    type = "A"
    ttl = 300
    managed_zone = data.google_dns_managed_zone.dns_zone.name
    rrdatas = [google_compute_global_address.website_ip.address]
}

# Add a bucket as a CDN backend
resource "google_compute_backend_bucket" "website-backend" {
    name = "website-backend"
    bucket_name = google_storage_bucket.website.name
    description = "Contains file for the website"
    enable_cdn = true
}

# Create a URL map
resource "google_compute_url_map" "website-map" {
    name = "webiste-url-map"
    default_service = google_compute_backend_bucket.website-backend.self_link
    host_rule {
      hosts =["*"]
      path_matcher = "allpaths"
    }
    path_matcher {
      name = "allpaths"
      default_service = google_compute_backend_bucket.website-backend.self_link
    }
}

# GCP HTTP Proxy
resource "google_compute_target_https_proxy" "website-proxy" {
    name = "website-target-proxy"
    url_map = google_compute_url_map.website-map.self_link
    ssl_certificates = [google_compute_managed_ssl_certificate.website-cert.id]
}

# GCP forwarding rule
resource "google_compute_global_forwarding_rule" "default" {
    name = "website-forwarding-rule"
    load_balancing_scheme = "EXTERNAL"
    ip_address = google_compute_global_address.website_ip.address
    ip_protocol = "TCP"
    port_range = "443"
    target = google_compute_target_https_proxy.website-proxy.self_link
}

# Create HTTPS certificate
resource "google_compute_managed_ssl_certificate" "website-cert" {
  provider = google-beta
  name     = "website-cert-2"
  managed {
    domains = [google_dns_record_set.website.name]
  }
}