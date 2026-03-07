const { parseJSONBody } = require("./common/request");
const { ok, unauthorized, badRequest, serverError } = require("./common/response");
const { requireSessionUser } = require("./common/session");
const { commitHold, buildProfile } = require("./common/membership");

exports.main = async (event) => {
  try {
    const session = await requireSessionUser(event);
    const body = parseJSONBody(event);

    const holdID = String(body.hold_id || "").trim();
    const requestID = String(body.request_id || "").trim();
    const actualUsage = typeof body.actual_usage === "object" && body.actual_usage ? body.actual_usage : {};
    const actualPoints = body.actual_points != null ? Number(body.actual_points) : undefined;
    const payload = typeof body.payload === "object" && body.payload ? body.payload : {};

    if (!holdID || !requestID) {
      return badRequest("缺少必要参数");
    }

    const hold = await commitHold({
      uid: session.uid,
      holdID,
      requestID,
      actualUsage,
      actualPoints,
      payload,
    });
    const profile = await buildProfile(session.uid);

    return ok({
      hold_id: hold.hold_id,
      committed_points: hold.committed_points || 0,
      profile,
    });
  } catch (error) {
    if (error?.code === "UNAUTHORIZED") {
      return unauthorized(error.message || "未登录");
    }
    if (error?.code === "BAD_REQUEST") {
      return badRequest(error.message || "结算失败");
    }
    console.error("membership_hold_commit failed", error);
    return serverError(error.message || "结算失败");
  }
};
