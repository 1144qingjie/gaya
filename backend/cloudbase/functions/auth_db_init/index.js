const { db } = require("./common/cloudbase");
const { parseJSONBody } = require("./common/request");

const TARGET_COLLECTIONS = [
  "app_users",
  "phone_identities",
  "auth_challenges",
  "auth_rate_limits",
  "membership_subscriptions",
  "membership_quota_buckets",
  "membership_points_holds",
  "membership_points_ledger",
  "membership_binding_history",
];

function ok(data) {
  return {
    code: 0,
    message: "ok",
    data,
  };
}

function serverError(message) {
  return {
    code: 500,
    message,
  };
}

function parseInput(event) {
  if (event && typeof event === "object" && !event.body) {
    return event;
  }
  return parseJSONBody(event);
}

function isCollectionExistsError(error) {
  const text = `${error?.message || ""} ${error?.code || ""}`.toLowerCase();
  return text.includes("already exists") || text.includes("exist");
}

async function ensureCollection(collectionName) {
  try {
    await db().createCollection(collectionName);
    return {
      collection: collectionName,
      status: "created",
    };
  } catch (error) {
    if (isCollectionExistsError(error)) {
      return {
        collection: collectionName,
        status: "exists",
      };
    }
    throw error;
  }
}

async function ensureUserSeed(user) {
  const uid = String(user?.uid || "").trim();
  if (!uid) {
    return null;
  }

  const nickname = String(user?.nickname || "").trim() || "会员联调用户";
  const registerMethod = String(user?.register_method || "").trim() || "smoke_seed";
  const now = new Date().toISOString();
  const lookup = await db().collection("app_users").where({ uid }).limit(1).get();
  const existing = lookup?.data?.[0];

  if (existing?._id) {
    await db().collection("app_users").doc(existing._id).update({
      nickname,
      register_method: registerMethod,
      updated_at: now,
    });

    return {
      uid,
      nickname,
      register_method: registerMethod,
      status: "updated",
    };
  }

  await db().collection("app_users").add({
    uid,
    nickname,
    register_method: registerMethod,
    created_at: now,
    updated_at: now,
  });

  return {
    uid,
    nickname,
    register_method: registerMethod,
    status: "created",
  };
}

exports.main = async (event) => {
  try {
    const input = parseInput(event);
    const result = [];
    for (const name of TARGET_COLLECTIONS) {
      // createCollection is idempotent in this flow:
      // existing collection returns "exists".
      const row = await ensureCollection(name);
      result.push(row);
    }

    const usersToSeed = Array.isArray(input?.users_to_seed) ? input.users_to_seed : [];
    const seededUsers = [];
    for (const item of usersToSeed) {
      const seeded = await ensureUserSeed(item);
      if (seeded) {
        seededUsers.push(seeded);
      }
    }

    return ok({
      collections: result,
      seeded_users: seededUsers,
    });
  } catch (error) {
    console.error("auth_db_init failed", error);
    return serverError(error.message || "db init failed");
  }
};
