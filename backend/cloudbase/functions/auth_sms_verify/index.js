const { parseJSONBody, getHeader, normalizeMainlandPhone } = require("./common/request");
const { ok, badRequest, unauthorized, serverError } = require("./common/response");
const { getChallenge, isChallengeExpired, markChallengeUsed } = require("./common/challenge");
const { checkSmsVerifyCode } = require("./common/pnvs");
const { findOrCreateUserByPhone } = require("./common/user");
const { issueSessionTokens } = require("./common/tokens");
const { sha256 } = require("./common/crypto");

exports.main = async (event) => {
  try {
    const body = parseJSONBody(event);
    const challengeId = String(body.challenge_id || "").trim();
    const verifyCode = String(body.verify_code || "").trim();
    const nickname = String(body.nickname || "").trim();
    const phone = normalizeMainlandPhone(body.phone_number);
    const agreementAccepted = Boolean(body.agreement_accepted);
    const deviceId = getHeader(event, "x-device-id");

    if (!agreementAccepted) {
      return unauthorized("请先同意用户协议与隐私政策");
    }
    if (!deviceId) {
      return badRequest("缺少设备标识");
    }
    if (!challengeId || !verifyCode || !phone) {
      return badRequest("参数不完整");
    }

    const challenge = await getChallenge(challengeId);
    if (!challenge?._id) {
      return badRequest("验证码会话不存在");
    }
    if (challenge.used) {
      return badRequest("验证码已使用，请重新获取");
    }
    if (isChallengeExpired(challenge)) {
      return badRequest("验证码已过期，请重新获取");
    }
    if (challenge.device_id !== deviceId) {
      return unauthorized("设备不匹配，请重新获取验证码");
    }
    if (challenge.phone_hash !== sha256(phone)) {
      return badRequest("手机号不匹配");
    }

    const result = await checkSmsVerifyCode(phone, verifyCode, challenge.biz_id || "");
    if (!result.verified) {
      return badRequest("验证码不正确");
    }

    await markChallengeUsed(challenge._id);

    const user = await findOrCreateUserByPhone({
      phoneE164: phone,
      nickname,
      registerMethod: "sms",
    });

    const tokens = issueSessionTokens(user.uid);

    return ok({
      user: {
        uid: user.uid,
        nickname: user.nickname,
        is_new_user: user.isNewUser,
      },
      session: tokens,
    });
  } catch (error) {
    console.error("auth_sms_verify failed", error);
    return serverError(error.message || "验证码登录失败");
  }
};
