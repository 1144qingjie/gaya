const { db } = require("./common/cloudbase");

const TARGET_COLLECTIONS = [
  "app_users",
  "phone_identities",
  "auth_challenges",
  "auth_rate_limits",
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

exports.main = async () => {
  try {
    const result = [];
    for (const name of TARGET_COLLECTIONS) {
      // createCollection is idempotent in this flow:
      // existing collection returns "exists".
      const row = await ensureCollection(name);
      result.push(row);
    }

    return ok({
      collections: result,
    });
  } catch (error) {
    console.error("auth_db_init failed", error);
    return serverError(error.message || "db init failed");
  }
};
