const jwt = require("jsonwebtoken");

const ACCESS_EXPIRES_IN = process.env.ACCESS_TOKEN_EXPIRES_IN || "2h";
const REFRESH_EXPIRES_IN = process.env.REFRESH_TOKEN_EXPIRES_IN || "30d";

function issueSessionTokens(uid) {
  const secret = process.env.APP_JWT_SECRET;
  if (!secret) {
    throw new Error("Missing APP_JWT_SECRET");
  }

  const accessToken = jwt.sign(
    {
      uid,
      type: "access",
    },
    secret,
    { expiresIn: ACCESS_EXPIRES_IN }
  );

  const refreshToken = jwt.sign(
    {
      uid,
      type: "refresh",
    },
    secret,
    { expiresIn: REFRESH_EXPIRES_IN }
  );

  return {
    access_token: accessToken,
    refresh_token: refreshToken,
    token_type: "Bearer",
    expires_in: 7200,
  };
}

module.exports = {
  issueSessionTokens,
};
