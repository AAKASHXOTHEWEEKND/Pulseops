"use strict";

const API = (window.PULSEOPS_CONFIG && window.PULSEOPS_CONFIG.apiBaseUrl) || "";
// When apiBaseUrl is empty we call the same origin via the /api prefix that
// nginx proxies to the API service.
const base = API ? API.replace(/\/$/, "") : "/api";

const $ = (id) => document.getElementById(id);
const pollers = new Map();

async function req(path, opts) {
  const res = await fetch(base + path, opts);
  if (!res.ok) {
    let detail = res.statusText;
    try { detail = (await res.json()).detail || detail; } catch (_) {}
    throw new Error(`${res.status}: ${detail}`);
  }
  return res.json();
}

async function checkHealth() {
  try {
    const data = await req("/health/ready");
    $("api-indicator").className = "dot ok";
    $("api-text").textContent = "ready";
    if (data.version) $("version").textContent = data.version;
  } catch (e) {
    $("api-indicator").className = "dot bad";
    $("api-text").textContent = "unavailable";
  }
}

function statusBadge(status) {
  return `<span class="badge ${status}">${status}</span>`;
}

function renderRows(jobs) {
  const body = $("jobs-body");
  if (!jobs.length) {
    body.innerHTML = '<tr><td colspan="5" class="empty">No jobs yet.</td></tr>';
    return;
  }
  body.innerHTML = jobs.map((j) => `
    <tr>
      <td class="mono">${j.id.slice(0, 8)}</td>
      <td>${escapeHtml(j.input)}</td>
      <td>${statusBadge(j.status)}</td>
      <td>${j.result ? escapeHtml(j.result) : (j.error ? '⚠ ' + escapeHtml(j.error) : "—")}</td>
      <td class="mono">${j.updated_at ? new Date(j.updated_at).toLocaleTimeString() : "—"}</td>
    </tr>`).join("");
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
  }[c]));
}

async function loadJobs() {
  try {
    const jobs = await req("/jobs");
    renderRows(jobs);
  } catch (e) {
    console.error(e);
  }
}

// Poll a single job until it reaches a terminal state, refreshing the table.
function pollJob(id) {
  if (pollers.has(id)) return;
  let attempts = 0;
  const timer = setInterval(async () => {
    attempts += 1;
    try {
      const job = await req(`/jobs/${id}`);
      await loadJobs();
      if (["COMPLETED", "FAILED"].includes(job.status) || attempts > 60) {
        clearInterval(timer);
        pollers.delete(id);
      }
    } catch (e) {
      clearInterval(timer);
      pollers.delete(id);
    }
  }, 1000);
  pollers.set(id, timer);
}

$("job-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const input = $("input").value.trim();
  const msg = $("submit-msg");
  if (!input) return;
  $("submit-btn").disabled = true;
  msg.className = "msg";
  msg.textContent = "Submitting…";
  try {
    const job = await req("/jobs", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ input }),
    });
    msg.className = "msg ok";
    msg.textContent = `Submitted job ${job.id.slice(0, 8)} (${job.status}).`;
    $("input").value = "";
    await loadJobs();
    pollJob(job.id);
  } catch (err) {
    msg.className = "msg error";
    msg.textContent = err.message;
  } finally {
    $("submit-btn").disabled = false;
  }
});

$("refresh-btn").addEventListener("click", loadJobs);

checkHealth();
loadJobs();
setInterval(checkHealth, 15000);
