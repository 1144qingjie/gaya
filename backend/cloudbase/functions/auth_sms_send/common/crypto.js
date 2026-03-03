const crypto = require("crypto");

function sha256(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex");
}

function maskMainlandPhone(phone) {
  const normalized = String(phone || "").replace(/^\+86/, "");
  if (!/^1\d{10}$/.test(normalized)) {
    return phone;
  }
  return `${normalized.slice(0, 3)}****${normalized.slice(-4)}`;
}

module.exports = {
  sha256,
  maskMainlandPhone,
};
