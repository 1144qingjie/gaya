const { db } = require("./cloudbase");

const SUBSCRIPTIONS = "membership_subscriptions";
const BUCKETS = "membership_quota_buckets";
const HOLDS = "membership_points_holds";
const LEDGER = "membership_points_ledger";
const BINDING_HISTORY = "membership_binding_history";

const FREE_DAILY_POINTS = 80;

const MEMBERSHIP_PLANS = [
  {
    plan_id: "monthly",
    name: "月卡",
    duration_days: 30,
    included_points: 3600,
    apple_product_id: "com.gaya.membership.monthly",
    auto_renewable: true,
    sort_order: 1,
  },
  {
    plan_id: "quarterly",
    name: "季卡",
    duration_days: 90,
    included_points: 12000,
    apple_product_id: "com.gaya.membership.quarterly",
    auto_renewable: true,
    sort_order: 2,
  },
];

const FEATURE_CATALOG = [
  {
    feature_key: "text_chat",
    name: "文本聊天",
    settlement_mode: "token_actual",
    unit_size: 100,
    points_per_unit: 1,
    pre_hold_points: 30,
    auto_trigger_charge: false,
    enabled: true,
  },
  {
    feature_key: "photo_caption",
    name: "照片文案",
    settlement_mode: "token_actual",
    unit_size: 100,
    points_per_unit: 2,
    pre_hold_points: 24,
    auto_trigger_charge: false,
    enabled: true,
  },
  {
    feature_key: "photo_conversation",
    name: "照片理解",
    settlement_mode: "token_actual",
    unit_size: 100,
    points_per_unit: 2,
    pre_hold_points: 36,
    auto_trigger_charge: false,
    enabled: true,
  },
  {
    feature_key: "photo_story_summary",
    name: "照片故事总结",
    settlement_mode: "token_actual",
    unit_size: 100,
    points_per_unit: 2,
    pre_hold_points: 24,
    auto_trigger_charge: true,
    enabled: true,
  },
  {
    feature_key: "memory_corridor_summary",
    name: "记忆回廊总结",
    settlement_mode: "token_actual",
    unit_size: 100,
    points_per_unit: 3,
    pre_hold_points: 80,
    auto_trigger_charge: true,
    enabled: true,
  },
  {
    feature_key: "memory_profile_extraction",
    name: "用户画像提取",
    settlement_mode: "token_actual",
    unit_size: 100,
    points_per_unit: 2,
    pre_hold_points: 80,
    auto_trigger_charge: true,
    enabled: true,
  },
  {
    feature_key: "memory_emotion_analysis",
    name: "情绪分析",
    settlement_mode: "token_actual",
    unit_size: 100,
    points_per_unit: 1,
    pre_hold_points: 12,
    auto_trigger_charge: true,
    enabled: true,
  },
  {
    feature_key: "memory_retrieval",
    name: "记忆检索",
    settlement_mode: "token_actual",
    unit_size: 100,
    points_per_unit: 1,
    pre_hold_points: 40,
    auto_trigger_charge: true,
    enabled: true,
  },
  {
    feature_key: "voice_conversation",
    name: "语音对话",
    settlement_mode: "duration_estimate",
    unit_size: 60,
    points_per_unit: 12,
    pre_hold_points: 18,
    auto_trigger_charge: false,
    enabled: true,
  },
];

function nowISO(date = new Date()) {
  return date.toISOString();
}

function createID(prefix) {
  return `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
}

function parseISODate(value) {
  const text = String(value || "").trim();
  if (!text) {
    return null;
  }
  const date = new Date(text);
  return Number.isNaN(date.getTime()) ? null : date;
}

function startOfChinaDay(date = new Date()) {
  const shifted = new Date(date.getTime() + 8 * 60 * 60 * 1000);
  shifted.setUTCHours(0, 0, 0, 0);
  return new Date(shifted.getTime() - 8 * 60 * 60 * 1000);
}

function addDays(date, days) {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function bucketAvailablePoints(bucket) {
  return Math.max(
    0,
    Number(bucket.total_points || 0) -
      Number(bucket.used_points || 0) -
      Number(bucket.frozen_points || 0)
  );
}

function sanitizePoints(value) {
  return Math.max(0, Math.ceil(Number(value || 0)));
}

function getPlanCatalog() {
  return MEMBERSHIP_PLANS.map((item) => ({ ...item }));
}

function getFeatureCatalog() {
  return FEATURE_CATALOG.map((item) => ({ ...item }));
}

function findPlanByID(planID) {
  return MEMBERSHIP_PLANS.find((item) => item.plan_id === planID) || null;
}

function findPlanByProductID(productID) {
  return MEMBERSHIP_PLANS.find((item) => item.apple_product_id === productID) || null;
}

function findFeatureByKey(featureKey) {
  return FEATURE_CATALOG.find((item) => item.feature_key === featureKey) || null;
}

async function addDocumentWithResolvedID(collectionName, document, lookup = {}) {
  const addResult = await db().collection(collectionName).add(document);
  const docID =
    addResult?.id ||
    addResult?._id ||
    addResult?.insertedId ||
    addResult?.data?._id ||
    "";

  if (docID) {
    return {
      ...document,
      _id: docID,
    };
  }

  if (!lookup || Object.keys(lookup).length === 0) {
    return document;
  }

  const result = await db()
    .collection(collectionName)
    .where(lookup)
    .limit(1)
    .get();

  const row = result?.data?.[0];
  return row ? { ...document, ...row } : document;
}

async function findLatestSubscriptionByUID(uid) {
  const result = await db()
    .collection(SUBSCRIPTIONS)
    .where({ uid })
    .get();

  const rows = (result?.data || []).sort((lhs, rhs) =>
    String(rhs.updated_at || "").localeCompare(String(lhs.updated_at || ""))
  );
  return rows[0] || null;
}

async function findSubscriptionByOriginalTransactionID(originalTransactionID) {
  const result = await db()
    .collection(SUBSCRIPTIONS)
    .where({ original_transaction_id: originalTransactionID })
    .limit(1)
    .get();

  return result?.data?.[0] || null;
}

async function findActivePlanBucket(uid, subscriptionID) {
  const result = await db()
    .collection(BUCKETS)
    .where({
      uid,
      bucket_type: "plan_period",
      subscription_id: subscriptionID,
      status: "active",
    })
    .get();

  const rows = (result?.data || []).sort((lhs, rhs) =>
    String(rhs.expires_at || "").localeCompare(String(lhs.expires_at || ""))
  );
  return rows[0] || null;
}

async function expireBucket(bucket, reason = "expired") {
  if (!bucket?._id || bucket.status === "expired") {
    return bucket;
  }

  const now = nowISO();
  const available = bucketAvailablePoints(bucket);
  await db().collection(BUCKETS).doc(bucket._id).update({
    status: "expired",
    frozen_points: 0,
    remaining_points: 0,
    expired_reason: reason,
    updated_at: now,
  });

  if (available > 0) {
    await appendLedger({
      uid: bucket.uid,
      bucket_id: bucket.bucket_id,
      feature_key: "",
      biz_type: "expire",
      points_delta: -available,
      request_id: "",
      payload: { reason },
    });
  }

  return {
    ...bucket,
    status: "expired",
    frozen_points: 0,
    remaining_points: 0,
  };
}

async function expireSubscription(subscription, reason = "expired") {
  if (!subscription?._id || subscription.status === "expired") {
    return subscription;
  }

  const now = nowISO();
  await db().collection(SUBSCRIPTIONS).doc(subscription._id).update({
    status: "expired",
    updated_at: now,
    expired_reason: reason,
  });

  const bucket = await findActivePlanBucket(subscription.uid, subscription.subscription_id);
  if (bucket) {
    await expireBucket(bucket, reason);
  }

  return {
    ...subscription,
    status: "expired",
  };
}

async function refreshSubscriptionState(uid) {
  const subscription = await findLatestSubscriptionByUID(uid);
  if (!subscription) {
    return null;
  }

  const expiresAt = parseISODate(subscription.expires_at);
  if (subscription.status === "active" && expiresAt && expiresAt <= new Date()) {
    return expireSubscription(subscription, "subscription_expired");
  }

  return subscription;
}

async function appendLedger({
  uid,
  bucket_id,
  feature_key,
  biz_type,
  points_delta,
  request_id,
  payload,
}) {
  const now = nowISO();
  await db().collection(LEDGER).add({
    ledger_id: createID("ledger"),
    uid,
    bucket_id: bucket_id || "",
    feature_key: feature_key || "",
    biz_type,
    points_delta: Number(points_delta || 0),
    request_id: request_id || "",
    created_at: now,
    updated_at: now,
    payload: payload || {},
  });
}

async function ensureDailyFreeBucket(uid) {
  const now = new Date();
  const dayStart = startOfChinaDay(now);
  const nextDay = addDays(dayStart, 1);
  const dayKey = nowISO(dayStart).slice(0, 10);

  const result = await db()
    .collection(BUCKETS)
    .where({
      uid,
      bucket_type: "free_daily",
      day_key: dayKey,
      status: "active",
    })
    .limit(1)
    .get();

  const existing = result?.data?.[0];
  if (existing) {
    return existing;
  }

  const bucketID = createID("bucket");
  const nowText = nowISO();
  const bucket = {
    bucket_id: bucketID,
    uid,
    bucket_type: "free_daily",
    plan_id: "",
    subscription_id: "",
    total_points: FREE_DAILY_POINTS,
    used_points: 0,
    frozen_points: 0,
    remaining_points: FREE_DAILY_POINTS,
    starts_at: nowISO(dayStart),
    expires_at: nowISO(nextDay),
    day_key: dayKey,
    status: "active",
    created_at: nowText,
    updated_at: nowText,
  };

  const createdBucket = await addDocumentWithResolvedID(BUCKETS, bucket, { bucket_id: bucketID });
  await appendLedger({
    uid,
    bucket_id: bucketID,
    feature_key: "",
    biz_type: "grant",
    points_delta: FREE_DAILY_POINTS,
    request_id: "",
      payload: { bucket_type: "free_daily", day_key: dayKey },
  });
  return createdBucket;
}

async function resolveAvailableBucket(uid) {
  const subscription = await refreshSubscriptionState(uid);
  if (subscription && subscription.status === "active") {
    const bucket = await findActivePlanBucket(uid, subscription.subscription_id);
    if (bucket) {
      const expiresAt = parseISODate(bucket.expires_at);
      if (bucket.status === "active" && expiresAt && expiresAt > new Date()) {
        return bucket;
      }
      if (expiresAt && expiresAt <= new Date()) {
        await expireBucket(bucket);
      }
    }
  }

  return ensureDailyFreeBucket(uid);
}

async function buildProfile(uid) {
  const activeSubscription = await refreshSubscriptionState(uid);
  const bucket = await resolveAvailableBucket(uid);
  const availablePoints = bucket ? bucketAvailablePoints(bucket) : 0;
  const plan = activeSubscription ? findPlanByID(activeSubscription.plan_id) : null;

  return {
    free_daily_points: FREE_DAILY_POINTS,
    plans: getPlanCatalog(),
    feature_catalog: getFeatureCatalog(),
    current_membership: activeSubscription && plan
      ? {
          plan_id: activeSubscription.plan_id,
          plan_name: plan.name,
          status: activeSubscription.status,
          started_at: activeSubscription.started_at,
          expires_at: activeSubscription.expires_at,
          auto_renew_status: Boolean(activeSubscription.auto_renew_status),
          original_transaction_id: activeSubscription.original_transaction_id,
          latest_transaction_id: activeSubscription.latest_transaction_id,
        }
      : null,
    active_bucket: bucket
      ? {
          bucket_id: bucket.bucket_id,
          bucket_type: bucket.bucket_type,
          total_points: Number(bucket.total_points || 0),
          used_points: Number(bucket.used_points || 0),
          frozen_points: Number(bucket.frozen_points || 0),
          remaining_points: bucketAvailablePoints(bucket),
          expires_at: bucket.expires_at,
        }
      : null,
    current_role: activeSubscription && activeSubscription.status === "active" ? "membership" : "free",
    spendable_points: availablePoints,
  };
}

async function createHold({ uid, featureKey, requestID, estimatedPoints, payload = {} }) {
  const feature = findFeatureByKey(featureKey);
  if (!feature || !feature.enabled) {
    const error = new Error("当前功能暂不可用");
    error.code = "BAD_REQUEST";
    throw error;
  }

  const existing = await db()
    .collection(HOLDS)
    .where({ uid, request_id: requestID, feature_key: featureKey })
    .limit(1)
    .get();

  const existingHold = existing?.data?.[0];
  if (existingHold) {
    return existingHold;
  }

  const bucket = await resolveAvailableBucket(uid);
  if (!bucket) {
    const error = new Error("当前无可用积分");
    error.code = "BAD_REQUEST";
    throw error;
  }

  const points = sanitizePoints(estimatedPoints || feature.pre_hold_points);
  if (bucketAvailablePoints(bucket) < points) {
    const error = new Error("积分不足，请先开通会员或等待次日免费积分刷新");
    error.code = "BAD_REQUEST";
    throw error;
  }

  const nextFrozen = Number(bucket.frozen_points || 0) + points;
  const nextRemaining = Math.max(
    0,
    Number(bucket.total_points || 0) - Number(bucket.used_points || 0) - nextFrozen
  );
  const now = nowISO();

  await db().collection(BUCKETS).doc(bucket._id).update({
    frozen_points: nextFrozen,
    remaining_points: nextRemaining,
    updated_at: now,
  });

  const hold = {
    hold_id: createID("hold"),
    uid,
    bucket_id: bucket.bucket_id,
    bucket_doc_id: bucket._id,
    feature_key: featureKey,
    request_id: requestID,
    hold_points: points,
    status: "active",
    created_at: now,
    updated_at: now,
    expires_at: nowISO(new Date(Date.now() + 5 * 60 * 1000)),
    payload,
  };

  await db().collection(HOLDS).add(hold);
  await appendLedger({
    uid,
    bucket_id: bucket.bucket_id,
    feature_key: featureKey,
    biz_type: "freeze",
    points_delta: -points,
    request_id: requestID,
    payload: { hold_id: hold.hold_id },
  });

  return hold;
}

function calculateActualPoints(feature, actualUsage = {}, fallbackPoints = 0) {
  if (!feature) {
    return sanitizePoints(fallbackPoints);
  }

  if (feature.settlement_mode === "duration_estimate") {
    const seconds = Math.max(0, Number(actualUsage.billable_seconds || 0));
    return Math.max(
      0,
      Math.ceil((seconds * Number(feature.points_per_unit || 0)) / Number(feature.unit_size || 60))
    );
  }

  const totalTokens = Math.max(0, Number(actualUsage.total_tokens || 0));
  const unitSize = Math.max(1, Number(feature.unit_size || 100));
  const units = Math.ceil(totalTokens / unitSize);
  return Math.max(0, units * Number(feature.points_per_unit || 0));
}

async function commitHold({ uid, holdID, requestID, actualUsage = {}, actualPoints, payload = {} }) {
  const holdLookup = await db()
    .collection(HOLDS)
    .where({ uid, hold_id: holdID, request_id: requestID })
    .limit(1)
    .get();

  const hold = holdLookup?.data?.[0];
  if (!hold) {
    const error = new Error("冻结单不存在");
    error.code = "BAD_REQUEST";
    throw error;
  }

  if (hold.status === "committed") {
    return hold;
  }

  if (hold.status !== "active") {
    const error = new Error("冻结单状态不可提交");
    error.code = "BAD_REQUEST";
    throw error;
  }

  const feature = findFeatureByKey(hold.feature_key);
  const points = sanitizePoints(
    actualPoints != null ? actualPoints : calculateActualPoints(feature, actualUsage, hold.hold_points)
  );
  const bucketLookup = await db()
    .collection(BUCKETS)
    .where({ bucket_id: hold.bucket_id, uid })
    .limit(1)
    .get();
  const bucket = bucketLookup?.data?.[0];

  if (!bucket) {
    const error = new Error("积分桶不存在");
    error.code = "BAD_REQUEST";
    throw error;
  }

  const currentFrozen = Math.max(0, Number(bucket.frozen_points || 0) - Number(hold.hold_points || 0));
  const availableAfterRelease = Math.max(
    0,
    Number(bucket.total_points || 0) - Number(bucket.used_points || 0) - currentFrozen
  );
  const extraNeeded = Math.max(0, points - Number(hold.hold_points || 0));
  const extraCharged = Math.min(extraNeeded, availableAfterRelease);
  const finalCharged = Math.min(points, Number(hold.hold_points || 0) + extraCharged);
  const nextUsed = Number(bucket.used_points || 0) + finalCharged;
  const nextFrozen = currentFrozen;
  const nextRemaining = Math.max(0, Number(bucket.total_points || 0) - nextUsed - nextFrozen);
  const now = nowISO();

  await db().collection(BUCKETS).doc(bucket._id).update({
    used_points: nextUsed,
    frozen_points: nextFrozen,
    remaining_points: nextRemaining,
    updated_at: now,
  });

  await db().collection(HOLDS).doc(hold._id).update({
    status: "committed",
    committed_points: finalCharged,
    actual_usage: actualUsage,
    payload: {
      ...(hold.payload || {}),
      ...(payload || {}),
    },
    updated_at: now,
  });

  const releaseBack = Math.max(0, Number(hold.hold_points || 0) - finalCharged);
  if (releaseBack > 0) {
    await appendLedger({
      uid,
      bucket_id: bucket.bucket_id,
      feature_key: hold.feature_key,
      biz_type: "release",
      points_delta: releaseBack,
      request_id: requestID,
      payload: { hold_id: hold.hold_id, reason: "settlement_adjustment" },
    });
  }

  await appendLedger({
    uid,
    bucket_id: bucket.bucket_id,
    feature_key: hold.feature_key,
    biz_type: "commit",
    points_delta: -finalCharged,
    request_id: requestID,
    payload: { hold_id: hold.hold_id, actual_usage: actualUsage },
  });

  return {
    ...hold,
    status: "committed",
    committed_points: finalCharged,
  };
}

async function releaseHold({ uid, holdID, requestID, reason = "cancelled" }) {
  const holdLookup = await db()
    .collection(HOLDS)
    .where({ uid, hold_id: holdID, request_id: requestID })
    .limit(1)
    .get();

  const hold = holdLookup?.data?.[0];
  if (!hold) {
    const error = new Error("冻结单不存在");
    error.code = "BAD_REQUEST";
    throw error;
  }

  if (hold.status === "released") {
    return hold;
  }
  if (hold.status === "committed") {
    return hold;
  }

  const bucketLookup = await db()
    .collection(BUCKETS)
    .where({ bucket_id: hold.bucket_id, uid })
    .limit(1)
    .get();
  const bucket = bucketLookup?.data?.[0];
  const now = nowISO();

  if (bucket) {
    const nextFrozen = Math.max(0, Number(bucket.frozen_points || 0) - Number(hold.hold_points || 0));
    const nextRemaining = Math.max(
      0,
      Number(bucket.total_points || 0) - Number(bucket.used_points || 0) - nextFrozen
    );
    await db().collection(BUCKETS).doc(bucket._id).update({
      frozen_points: nextFrozen,
      remaining_points: nextRemaining,
      updated_at: now,
    });
  }

  await db().collection(HOLDS).doc(hold._id).update({
    status: "released",
    release_reason: reason,
    updated_at: now,
  });

  await appendLedger({
    uid,
    bucket_id: hold.bucket_id,
    feature_key: hold.feature_key,
    biz_type: "release",
    points_delta: Number(hold.hold_points || 0),
    request_id: requestID,
    payload: { hold_id: hold.hold_id, reason },
  });

  return {
    ...hold,
    status: "released",
  };
}

async function upsertPlanBucketForSubscription(subscription, plan, cycleStartISO, cycleExpiresISO) {
  const existing = await db()
    .collection(BUCKETS)
    .where({
      subscription_id: subscription.subscription_id,
      bucket_type: "plan_period",
      starts_at: cycleStartISO,
    })
    .limit(1)
    .get();

  const row = existing?.data?.[0];
  if (row) {
    return row;
  }

  const bucketID = createID("bucket");
  const now = nowISO();
  const bucket = {
    bucket_id: bucketID,
    uid: subscription.uid,
    bucket_type: "plan_period",
    plan_id: plan.plan_id,
    subscription_id: subscription.subscription_id,
    total_points: plan.included_points,
    used_points: 0,
    frozen_points: 0,
    remaining_points: plan.included_points,
    starts_at: cycleStartISO,
    expires_at: cycleExpiresISO,
    status: "active",
    created_at: now,
    updated_at: now,
  };

  const createdBucket = await addDocumentWithResolvedID(BUCKETS, bucket, {
    bucket_id: bucketID,
  });
  await appendLedger({
    uid: subscription.uid,
    bucket_id: bucketID,
    feature_key: "",
    biz_type: "grant",
    points_delta: plan.included_points,
    request_id: "",
    payload: {
      bucket_type: "plan_period",
      plan_id: plan.plan_id,
      subscription_id: subscription.subscription_id,
    },
  });
  return createdBucket;
}

async function migrateSubscriptionBinding({
  subscription,
  fromUID,
  toUID,
  trigger = "restore",
}) {
  const now = nowISO();
  await db().collection(SUBSCRIPTIONS).doc(subscription._id).update({
    uid: toUID,
    updated_at: now,
  });

  const buckets = await db()
    .collection(BUCKETS)
    .where({
      subscription_id: subscription.subscription_id,
      status: "active",
    })
    .get();

  for (const bucket of buckets?.data || []) {
    await db().collection(BUCKETS).doc(bucket._id).update({
      uid: toUID,
      updated_at: now,
    });
  }

  await db().collection(BINDING_HISTORY).add({
    binding_id: createID("binding"),
    subscription_id: subscription.subscription_id,
    original_transaction_id: subscription.original_transaction_id,
    from_uid: fromUID,
    to_uid: toUID,
    trigger,
    created_at: now,
    updated_at: now,
  });

  return {
    ...subscription,
    uid: toUID,
  };
}

async function syncSubscriptionFromPurchase({
  uid,
  planID,
  productID,
  originalTransactionID,
  latestTransactionID,
  autoRenewStatus,
  purchaseDateISO,
  expiresAtISO,
  trigger = "purchase",
}) {
  const plan = findPlanByID(planID) || findPlanByProductID(productID);
  if (!plan) {
    const error = new Error("无效的套餐");
    error.code = "BAD_REQUEST";
    throw error;
  }

  const rootTransactionID = String(originalTransactionID || latestTransactionID || "").trim() || createID("txroot");
  const transactionID = String(latestTransactionID || "").trim() || createID("tx");
  const purchaseDate = parseISODate(purchaseDateISO) || new Date();
  const expiresAt = parseISODate(expiresAtISO) || addDays(purchaseDate, plan.duration_days);
  const cycleStartISO = nowISO(purchaseDate);
  const cycleExpiresISO = nowISO(expiresAt);
  const now = nowISO();

  let subscription = await findSubscriptionByOriginalTransactionID(rootTransactionID);
  if (subscription && subscription.uid !== uid) {
    subscription = await migrateSubscriptionBinding({
      subscription,
      fromUID: subscription.uid,
      toUID: uid,
      trigger,
    });
  }

  if (subscription) {
    await db().collection(SUBSCRIPTIONS).doc(subscription._id).update({
      uid,
      plan_id: plan.plan_id,
      product_id: plan.apple_product_id,
      latest_transaction_id: transactionID,
      auto_renew_status: Boolean(autoRenewStatus),
      status: "active",
      started_at: cycleStartISO,
      expires_at: cycleExpiresISO,
      updated_at: now,
    });

    const refreshed = {
      ...subscription,
      uid,
      plan_id: plan.plan_id,
      product_id: plan.apple_product_id,
      latest_transaction_id: transactionID,
      auto_renew_status: Boolean(autoRenewStatus),
      status: "active",
      started_at: cycleStartISO,
      expires_at: cycleExpiresISO,
    };
    await upsertPlanBucketForSubscription(refreshed, plan, cycleStartISO, cycleExpiresISO);
    return refreshed;
  }

  const subscriptionID = createID("sub");
  const newSubscription = {
    subscription_id: subscriptionID,
    uid,
    plan_id: plan.plan_id,
    product_id: plan.apple_product_id,
    status: "active",
    started_at: cycleStartISO,
    expires_at: cycleExpiresISO,
    auto_renew_status: Boolean(autoRenewStatus),
    original_transaction_id: rootTransactionID,
    latest_transaction_id: transactionID,
    created_at: now,
    updated_at: now,
  };

  await db().collection(SUBSCRIPTIONS).add(newSubscription);
  await upsertPlanBucketForSubscription(newSubscription, plan, cycleStartISO, cycleExpiresISO);
  return newSubscription;
}

async function restoreSubscriptionForUID({ uid, originalTransactionID, latestTransactionID, purchaseDateISO, expiresAtISO }) {
  const originalID = String(originalTransactionID || "").trim();
  if (!originalID) {
    const error = new Error("缺少 original_transaction_id");
    error.code = "BAD_REQUEST";
    throw error;
  }

  const existing = await findSubscriptionByOriginalTransactionID(originalID);
  if (!existing) {
    const error = new Error("未找到可恢复的订阅");
    error.code = "BAD_REQUEST";
    throw error;
  }

  const plan = findPlanByID(existing.plan_id);
  return syncSubscriptionFromPurchase({
    uid,
    planID: existing.plan_id,
    productID: existing.product_id,
    originalTransactionID: originalID,
    latestTransactionID: latestTransactionID || existing.latest_transaction_id,
    autoRenewStatus: existing.auto_renew_status,
    purchaseDateISO: purchaseDateISO || existing.started_at,
    expiresAtISO: expiresAtISO || existing.expires_at,
    trigger: "restore",
    plan,
  });
}

async function listLedger(uid, limit = 50) {
  const result = await db()
    .collection(LEDGER)
    .where({ uid })
    .get();

  const rows = (result?.data || []).sort((lhs, rhs) =>
    String(rhs.created_at || "").localeCompare(String(lhs.created_at || ""))
  );
  return rows.slice(0, limit);
}

module.exports = {
  FREE_DAILY_POINTS,
  getPlanCatalog,
  getFeatureCatalog,
  findPlanByID,
  findPlanByProductID,
  findFeatureByKey,
  buildProfile,
  createHold,
  commitHold,
  releaseHold,
  syncSubscriptionFromPurchase,
  restoreSubscriptionForUID,
  listLedger,
};
