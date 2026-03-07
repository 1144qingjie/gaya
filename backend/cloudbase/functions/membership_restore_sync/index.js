const { parseJSONBody } = require("./common/request");
const { ok, unauthorized, badRequest, serverError } = require("./common/response");
const { requireSessionUser } = require("./common/session");
const { restoreSubscriptionForUID, buildProfile } = require("./common/membership");

exports.main = async (event) => {
  try {
    const session = await requireSessionUser(event);
    const body = parseJSONBody(event);

    const originalTransactionID = String(body.original_transaction_id || "").trim();
    const latestTransactionID = String(body.latest_transaction_id || "").trim();
    const purchaseDateISO = String(body.purchase_date || "").trim();
    const expiresAtISO = String(body.expires_at || "").trim();

    if (!originalTransactionID) {
      return badRequest("缺少 original_transaction_id");
    }

    await restoreSubscriptionForUID({
      uid: session.uid,
      originalTransactionID,
      latestTransactionID,
      purchaseDateISO,
      expiresAtISO,
    });

    const profile = await buildProfile(session.uid);
    return ok(profile);
  } catch (error) {
    if (error?.code === "UNAUTHORIZED") {
      return unauthorized(error.message || "未登录");
    }
    if (error?.code === "BAD_REQUEST") {
      return badRequest(error.message || "恢复购买失败");
    }
    console.error("membership_restore_sync failed", error);
    return serverError(error.message || "恢复购买失败");
  }
};
