const { parseJSONBody, getHeader } = require("./common/request");
const { ok, badRequest, unauthorized, serverError } = require("./common/response");
const { getMobileByOneTapToken } = require("./common/pnvs");
const { findOrCreateUserByPhone } = require("./common/user");
const { issueSessionTokens } = require("./common/tokens");

exports.main = async (event) => {
  try {
    const body = parseJSONBody(event);
    const oneTapToken = String(body.one_tap_token || "").trim();
    const nickname = String(body.nickname || "").trim();
    const agreementAccepted = Boolean(body.agreement_accepted);
    const deviceId = getHeader(event, "x-device-id");

    if (!agreementAccepted) {
      return unauthorized("请先同意用户协议与隐私政策");
    }
    if (!deviceId) {
      return badRequest("缺少设备标识");
    }
    if (!oneTapToken) {
      return badRequest("缺少一键登录 token");
    }

    const oneTapResult = await getMobileByOneTapToken(oneTapToken);
    const user = await findOrCreateUserByPhone({
      phoneE164: oneTapResult.phone,
      nickname,
      registerMethod: "onetap",
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
    console.error("auth_onetap_login failed", error);
    return serverError(error.message || "一键登录失败");
  }
};
