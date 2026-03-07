const { parseJSONBody } = require("./common/request");
const { ok, unauthorized, badRequest, serverError } = require("./common/response");
const { requireSessionUser } = require("./common/session");
const { releaseHold, buildProfile } = require("./common/membership");

exports.main = async (event) => {
  try {
    const session = await requireSessionUser(event);
    const body = parseJSONBody(event);

    const holdID = String(body.hold_id || "").trim();
    const requestID = String(body.request_id || "").trim();
    const reason = String(body.reason || "").trim() || "cancelled";

    if (!holdID || !requestID) {
      return badRequest("缺少必要参数");
    }

    const hold = await releaseHold({
      uid: session.uid,
      holdID,
      requestID,
      reason,
    });
    const profile = await buildProfile(session.uid);

    return ok({
      hold_id: hold.hold_id,
      profile,
    });
  } catch (error) {
    if (error?.code === "UNAUTHORIZED") {
      return unauthorized(error.message || "未登录");
    }
    if (error?.code === "BAD_REQUEST") {
      return badRequest(error.message || "释放冻结失败");
    }
    console.error("membership_hold_release failed", error);
    return serverError(error.message || "释放冻结失败");
  }
};
