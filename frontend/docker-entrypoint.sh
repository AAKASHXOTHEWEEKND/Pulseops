#!/bin/sh
# Render runtime configuration from environment variables, then start nginx.
# This keeps the image immutable while letting each environment point at its
# own API upstream / base URL without a rebuild.
set -eu

: "${API_UPSTREAM:=api:8000}"      # nginx upstream (internal service:port)
: "${API_BASE_URL:=}"              # browser-facing base URL ("" => same-origin /api)

# 1) Templated nginx config (only ${API_UPSTREAM} is substituted).
envsubst '${API_UPSTREAM}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# 2) Runtime frontend config consumed by the browser.
cat > /usr/share/nginx/html/config.js <<EOF
window.PULSEOPS_CONFIG = { apiBaseUrl: "${API_BASE_URL}" };
EOF

exec nginx -g 'daemon off;'
