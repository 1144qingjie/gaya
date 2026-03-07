function parseJSONBody(event) {
  if (!event || !event.body) {
    return {};
  }
  if (typeof event.body === "object") {
    return event.body;
  }
  try {
    return JSON.parse(event.body);
  } catch (error) {
    return {};
  }
}

function getHeader(event, key) {
  const headers = event?.headers || {};
  const lower = key.toLowerCase();
  return headers[key] || headers[lower] || "";
}

function normalizeMainlandPhone(phone) {
  const cleaned = String(phone || "").replace(/\s+/g, "").replace(/-/g, "");
  if (/^1\d{10}$/.test(cleaned)) {
    return `+86${cleaned}`;
  }
  if (/^\+861\d{10}$/.test(cleaned)) {
    return cleaned;
  }
  return "";
}

module.exports = {
  parseJSONBody,
  getHeader,
  normalizeMainlandPhone,
};
