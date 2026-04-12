project_id  = "gearsnitch"
region      = "us-central1"
environment = "prod"
use_placeholder_images = false
domain      = "gearsnitch.com"

# Sensitive values — these are initial placeholders.
# Real values should be set via Secret Manager after terraform apply.
mongodb_uri = "mongodb+srv://gearsnitch-api:placeholder@gearsnitch-dev.sqrsvda.mongodb.net/gearsnitch?retryWrites=true&w=majority"
redis_url   = "redis://placeholder:6379"
