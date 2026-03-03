const { db } = require("./cloudbase");
const { sha256 } = require("./crypto");
const { randomUUID } = require("crypto");

const CHALLENGES = "auth_challenges";

function nowISO() {
  return new Date().toISOString();
}

function plusMinutesISO(minutes) {
  return new Date(Date.now() + minutes * 60 * 1000).toISOString();
}

async function createChallenge({ phoneE164, bizId, deviceId, ttlMinutes = 10 }) {
  const id = randomUUID();
  const now = nowISO();

  await db().collection(CHALLENGES).add({
    challenge_id: id,
    phone_hash: sha256(phoneE164),
    biz_id: bizId,
    device_id: deviceId,
    used: false,
    attempt_count: 0,
    expire_at: plusMinutesISO(ttlMinutes),
    created_at: now,
    updated_at: now,
  });

  return id;
}

async function getChallenge(challengeId) {
  const found = await db()
    .collection(CHALLENGES)
    .where({ challenge_id: challengeId })
    .limit(1)
    .get();

  return found?.data?.[0] || null;
}

async function markChallengeUsed(docId) {
  await db().collection(CHALLENGES).doc(docId).update({
    used: true,
    updated_at: nowISO(),
  });
}

function isChallengeExpired(challenge) {
  if (!challenge?.expire_at) {
    return true;
  }
  return Date.now() > new Date(challenge.expire_at).getTime();
}

module.exports = {
  createChallenge,
  getChallenge,
  markChallengeUsed,
  isChallengeExpired,
};
