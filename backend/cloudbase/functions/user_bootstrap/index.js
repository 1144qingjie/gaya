const { parseJSONBody } = require("./common/request");
const { ok, badRequest, serverError } = require("./common/response");
const { db } = require("./common/cloudbase");

exports.main = async (event) => {
  try {
    const body = parseJSONBody(event);
    const uid = String(body.uid || "").trim();
    const nickname = String(body.nickname || "").trim();

    if (!uid) {
      return badRequest("缺少 uid");
    }

    const now = new Date().toISOString();
    const found = await db().collection("app_users").where({ uid }).limit(1).get();
    const user = found?.data?.[0];

    if (!user?._id) {
      return badRequest("用户不存在");
    }

    const nextNickname = nickname || user.nickname || "用户";

    await db().collection("app_users").doc(user._id).update({
      nickname: nextNickname,
      updated_at: now,
    });

    return ok({ uid, nickname: nextNickname });
  } catch (error) {
    console.error("user_bootstrap failed", error);
    return serverError(error.message || "初始化用户信息失败");
  }
};
