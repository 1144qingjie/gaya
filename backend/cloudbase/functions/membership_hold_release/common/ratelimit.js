const { db } = require("./cloudbase");
const { sha256 } = require("./crypto");

const RATE_LIMITS = "auth_rate_limits";

async function allowSmsSend(phoneE164) {
  const key = sha256(`sms_send:${phoneE164}`);
  const now = Date.now();

  const hit = await db()
    .collection(RATE_LIMITS)
    .where({ key })
    .limit(1)
    .get();

  const row = hit?.data?.[0];
  if (!row) {
    await db().collection(RATE_LIMITS).add({
      key,
      last_sent_at: now,
      count_today: 1,
      day: new Date().toISOString().slice(0, 10),
    });
    return { allowed: true };
  }

  const sameDay = row.day === new Date().toISOString().slice(0, 10);
  const countToday = sameDay ? Number(row.count_today || 0) : 0;
  const cooldownMs = 60 * 1000;

  if (now - Number(row.last_sent_at || 0) < cooldownMs) {
    return { allowed: false, reason: "请稍后再试" };
  }

  if (countToday >= 10) {
    return { allowed: false, reason: "今日验证码发送次数已达上限" };
  }

  await db().collection(RATE_LIMITS).doc(row._id).update({
    last_sent_at: now,
    count_today: countToday + 1,
    day: new Date().toISOString().slice(0, 10),
  });

  return { allowed: true };
}

module.exports = {
  allowSmsSend,
};
