function json(statusCode, payload, headers = {}) {
  return {
    isBase64Encoded: false,
    statusCode,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...headers,
    },
    body: JSON.stringify(payload),
  };
}

function ok(data = {}) {
  return json(200, { code: 0, message: "ok", data });
}

function badRequest(message) {
  return json(400, { code: 400, message });
}

function unauthorized(message) {
  return json(401, { code: 401, message });
}

function tooManyRequests(message) {
  return json(429, { code: 429, message });
}

function serverError(message) {
  return json(500, { code: 500, message });
}

module.exports = {
  json,
  ok,
  badRequest,
  unauthorized,
  tooManyRequests,
  serverError,
};
