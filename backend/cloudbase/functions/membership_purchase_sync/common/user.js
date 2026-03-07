const { db } = require("./cloudbase");
const { maskMainlandPhone, sha256 } = require("./crypto");

const USERS = "app_users";
const PHONE_IDENTITIES = "phone_identities";

function nowISO() {
  return new Date().toISOString();
}

async function findUserByPhone(phoneE164) {
  const phoneHash = sha256(phoneE164);
  const lookup = await db()
    .collection(PHONE_IDENTITIES)
    .where({ phone_hash: phoneHash })
    .limit(1)
    .get();

  const identity = lookup?.data?.[0];
  if (!identity) {
    return null;
  }

  const users = await db()
    .collection(USERS)
    .where({ uid: identity.uid })
    .limit(1)
    .get();

  return users?.data?.[0] || null;
}

async function createUserByPhone({ phoneE164, nickname, registerMethod }) {
  const uid = `u_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const now = nowISO();
  const displayNickname = nickname || `用户${maskMainlandPhone(phoneE164).slice(-4)}`;
  const phoneHash = sha256(phoneE164);

  await db().collection(USERS).add({
    uid,
    nickname: displayNickname,
    created_at: now,
    updated_at: now,
    register_method: registerMethod,
  });

  await db().collection(PHONE_IDENTITIES).add({
    uid,
    phone_hash: phoneHash,
    phone_masked: maskMainlandPhone(phoneE164),
    last_login_at: now,
    created_at: now,
    updated_at: now,
  });

  return {
    uid,
    nickname: displayNickname,
  };
}

async function touchPhoneIdentity(phoneE164) {
  const phoneHash = sha256(phoneE164);
  const now = nowISO();
  const found = await db()
    .collection(PHONE_IDENTITIES)
    .where({ phone_hash: phoneHash })
    .limit(1)
    .get();

  const row = found?.data?.[0];
  if (!row?._id) {
    return;
  }

  await db().collection(PHONE_IDENTITIES).doc(row._id).update({
    last_login_at: now,
    updated_at: now,
  });
}

async function findOrCreateUserByPhone({ phoneE164, nickname = "", registerMethod }) {
  const existing = await findUserByPhone(phoneE164);
  if (existing) {
    await touchPhoneIdentity(phoneE164);
    return {
      uid: existing.uid,
      nickname: existing.nickname || nickname || "用户",
      isNewUser: false,
    };
  }

  const created = await createUserByPhone({
    phoneE164,
    nickname,
    registerMethod,
  });

  return {
    ...created,
    isNewUser: true,
  };
}

module.exports = {
  findOrCreateUserByPhone,
};
