const { parseJSONBody } = require("./common/request");
const { ok, unauthorized, badRequest, serverError } = require("./common/response");
const { requireSessionUser } = require("./common/session");
const { syncSubscriptionFromPurchase, buildProfile } = require("./common/membership");

exports.main = async (event) => {
  try {
    const session = await requireSessionUser(event);
    const body = parseJSONBody(event);

    const planID = String(body.plan_id || "").trim();
    const productID = String(body.product_id || "").trim();
    const originalTransactionID = String(body.original_transaction_id || "").trim();
    const latestTransactionID = String(body.latest_transaction_id || "").trim();
    const autoRenewStatus = body.auto_renew_status !== false;
    const purchaseDateISO = String(body.purchase_date || "").trim();
    const expiresAtISO = String(body.expires_at || "").trim();

    if (!planID && !productID) {
      return badRequest("缺少套餐信息");
    }

    await syncSubscriptionFromPurchase({
      uid: session.uid,
      planID,
      productID,
      originalTransactionID,
      latestTransactionID,
      autoRenewStatus,
      purchaseDateISO,
      expiresAtISO,
      trigger: "purchase",
    });

    const profile = await buildProfile(session.uid);
    return ok(profile);
  } catch (error) {
    if (error?.code === "UNAUTHORIZED") {
      return unauthorized(error.message || "未登录");
    }
    if (error?.code === "BAD_REQUEST") {
      return badRequest(error.message || "参数错误");
    }
    console.error("membership_purchase_sync failed", error);
    return serverError(error.message || "同步购买失败");
  }
};
