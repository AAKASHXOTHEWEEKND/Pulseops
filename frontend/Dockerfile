# syntax=docker/dockerfile:1.7
# Static frontend served by nginx-unprivileged (runs as non-root on :8080).
FROM nginxinc/nginx-unprivileged:1.27-alpine

# envsubst lives in gettext; add it for runtime config templating.
USER root
RUN apk add --no-cache gettext

# nginx config is a template; entrypoint renders it at start.
COPY nginx.conf /etc/nginx/nginx.conf.template
COPY docker-entrypoint.sh /usr/local/bin/pulseops-entrypoint.sh
COPY index.html styles.css app.js config.js /usr/share/nginx/html/

RUN chmod +x /usr/local/bin/pulseops-entrypoint.sh \
    && chown -R nginx:nginx /usr/share/nginx/html

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    API_UPSTREAM=api:8000 \
    API_BASE_URL=""

USER nginx
EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD wget -qO- http://localhost:8080/healthz || exit 1

ENTRYPOINT ["/usr/local/bin/pulseops-entrypoint.sh"]
