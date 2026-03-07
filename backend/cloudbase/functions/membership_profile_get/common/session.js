const jwt = require("jsonwebtoken");
const { getHeader } = require("./request");
const { db } = require("./cloudbase");

const USERS = "app_users";

function readBearerToken(event) {
  const raw = String(getHeader(event, "Authorization") || "").trim();
  if (!raw) {
    return "";
  }
  const match = raw.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : "";
}

function verifyAccessToken(token) {
  const secret = process.env.APP_JWT_SECRET;
  if (!secret) {
    throw new Error("Missing APP_JWT_SECRET");
  }
  const payload = jwt.verify(token, secret);
  if (!payload || payload.type !== "access" || !payload.uid) {
    throw new Error("Invalid access token");
  }
  return payload;
}

async function findUserByUID(uid) {
  const result = await db()
    .collection(USERS)
    .where({ uid })
    .limit(1)
    .get();

  return result?.data?.[0] || null;
}

async function requireSessionUser(event) {
  const token = readBearerToken(event);
  if (!token) {
    const error = new Error("缺少登录凭证");
    error.code = "UNAUTHORIZED";
    throw error;
  }

  let payload;
  try {
    payload = verifyAccessToken(token);
  } catch (error) {
    const unauthorized = new Error("登录状态已失效，请重新登录");
    unauthorized.code = "UNAUTHORIZED";
    throw unauthorized;
  }

  const user = await findUserByUID(payload.uid);
  if (!user) {
    const error = new Error("用户不存在");
    error.code = "UNAUTHORIZED";
    throw error;
  }

  return {
    uid: payload.uid,
    user,
    tokenPayload: payload,
  };
}

module.exports = {
  requireSessionUser,
  findUserByUID,
};
