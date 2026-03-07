const { ok, serverError } = require("./common/response");
const { FREE_DAILY_POINTS, getPlanCatalog, getFeatureCatalog } = require("./common/membership");

exports.main = async () => {
  try {
    return ok({
      free_daily_points: FREE_DAILY_POINTS,
      plans: getPlanCatalog(),
      feature_catalog: getFeatureCatalog(),
    });
  } catch (error) {
    console.error("membership_products_list failed", error);
    return serverError(error.message || "获取套餐列表失败");
  }
};
