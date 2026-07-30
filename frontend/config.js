// Runtime configuration. This file is regenerated at container start from the
// API_BASE_URL environment variable (see frontend/docker-entrypoint.sh), so the
// same image works in local / staging / production without a rebuild.
window.PULSEOPS_CONFIG = {
  // Empty string => same-origin (nginx proxies /api to the API service).
  apiBaseUrl: ""
};
