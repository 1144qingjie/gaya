const { ok, unauthorized, badRequest, serverError } = require("./common/response");
const { requireSessionUser } = require("./common/session");
const { buildProfile } = require("./common/membership");

exports.main = async (event) => {
  try {
    const session = await requireSessionUser(event);
    const profile = await buildProfile(session.uid);
    return ok(profile);
  } catch (error) {
    if (error?.code === "UNAUTHORIZED") {
      return unauthorized(error.message || "未登录");
    }
    if (error?.code === "BAD_REQUEST") {
      return badRequest(error.message || "参数错误");
    }
    console.error("membership_profile_get failed", error);
    return serverError(error.message || "获取会员资料失败");
  }
};
