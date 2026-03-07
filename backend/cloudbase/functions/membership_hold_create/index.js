const { parseJSONBody } = require("./common/request");
const { ok, unauthorized, badRequest, serverError } = require("./common/response");
const { requireSessionUser } = require("./common/session");
const { createHold, buildProfile } = require("./common/membership");

exports.main = async (event) => {
  try {
    const session = await requireSessionUser(event);
    const body = parseJSONBody(event);

    const featureKey = String(body.feature_key || "").trim();
    const requestID = String(body.request_id || "").trim();
    const estimatedPoints = Number(body.estimated_points || 0);
    const payload = typeof body.payload === "object" && body.payload ? body.payload : {};

    if (!featureKey || !requestID) {
      return badRequest("缺少必要参数");
    }

    const hold = await createHold({
      uid: session.uid,
      featureKey,
      requestID,
      estimatedPoints,
      payload,
    });
    const profile = await buildProfile(session.uid);

    return ok({
      hold_id: hold.hold_id,
      request_id: hold.request_id,
      hold_points: hold.hold_points,
      expires_at: hold.expires_at,
      profile,
    });
  } catch (error) {
    if (error?.code === "UNAUTHORIZED") {
      return unauthorized(error.message || "未登录");
    }
    if (error?.code === "BAD_REQUEST") {
      return badRequest(error.message || "创建冻结失败");
    }
    console.error("membership_hold_create failed", error);
    return serverError(error.message || "创建冻结失败");
  }
};
