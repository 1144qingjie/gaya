const { parseJSONBody, getHeader, normalizeMainlandPhone } = require("./common/request");
const { ok, badRequest, unauthorized, tooManyRequests, serverError } = require("./common/response");
const { sendSmsVerifyCode } = require("./common/pnvs");
const { createChallenge } = require("./common/challenge");
const { allowSmsSend } = require("./common/ratelimit");

exports.main = async (event) => {
  try {
    const body = parseJSONBody(event);
    const phone = normalizeMainlandPhone(body.phone_number);
    const agreementAccepted = Boolean(body.agreement_accepted);
    const deviceId = getHeader(event, "x-device-id");

    if (!agreementAccepted) {
      return unauthorized("请先同意用户协议与隐私政策");
    }
    if (!deviceId) {
      return badRequest("缺少设备标识");
    }
    if (!phone) {
      return badRequest("手机号格式不正确");
    }

    const rate = await allowSmsSend(phone);
    if (!rate.allowed) {
      return tooManyRequests(rate.reason || "验证码发送过于频繁");
    }

    const sms = await sendSmsVerifyCode(phone);
    const challengeId = await createChallenge({
      phoneE164: phone,
      bizId: sms.biz_id,
      deviceId,
      ttlMinutes: 10,
    });

    return ok({
      challenge_id: challengeId,
      resend_after_seconds: 60,
      expire_after_seconds: 600,
    });
  } catch (error) {
    console.error("auth_sms_send failed", error);
    return serverError(error.message || "验证码发送失败");
  }
};
