const { parseJSONBody } = require("./common/request");
const { ok, unauthorized, badRequest, serverError } = require("./common/response");
const { requireSessionUser } = require("./common/session");
const { listLedger } = require("./common/membership");

exports.main = async (event) => {
  try {
    const session = await requireSessionUser(event);
    const body = parseJSONBody(event);
    const limit = Math.max(1, Math.min(100, Number(body.limit || 30)));
    const items = await listLedger(session.uid, limit);
    return ok({ items });
  } catch (error) {
    if (error?.code === "UNAUTHORIZED") {
      return unauthorized(error.message || "未登录");
    }
    if (error?.code === "BAD_REQUEST") {
      return badRequest(error.message || "获取流水失败");
    }
    console.error("membership_ledger_list failed", error);
    return serverError(error.message || "获取流水失败");
  }
};
