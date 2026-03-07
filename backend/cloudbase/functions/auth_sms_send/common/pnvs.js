const Core = require("@alicloud/pop-core");

let cachedClient = null;

function client() {
  if (cachedClient) {
    return cachedClient;
  }

  const accessKeyId = process.env.ALIYUN_ACCESS_KEY_ID;
  const accessKeySecret = process.env.ALIYUN_ACCESS_KEY_SECRET;

  if (!accessKeyId || !accessKeySecret) {
    throw new Error("Missing Aliyun AK/SK env");
  }

  cachedClient = new Core({
    accessKeyId,
    accessKeySecret,
    endpoint: "https://dypnsapi.aliyuncs.com",
    apiVersion: "2017-05-25",
  });

  return cachedClient;
}

async function call(action, params) {
  const requestOption = {
    method: "POST",
  };

  return client().request(action, params, requestOption);
}

async function getMobileByOneTapToken(token) {
  const response = await call("GetMobile", {
    AccessToken: token,
    OutId: "gaya_onetap",
  });

  if (response?.Code !== "OK") {
    throw new Error(response?.Message || "GetMobile failed");
  }

  const phone =
    response?.GetMobileResultDTO?.Mobile || response?.PhoneNumber;
  if (!phone) {
    throw new Error("GetMobile missing phone number in response: " + JSON.stringify(response));
  }

  return {
    phone,
    request_id: response?.RequestId || "",
  };
}

async function sendSmsVerifyCode(phone) {
  const response = await call("SendSmsVerifyCode", {
    PhoneNumber: phone,
    SignName: process.env.PNVS_SMS_SIGN_NAME,
    TemplateCode: process.env.PNVS_SMS_TEMPLATE_CODE,
    OutId: "gaya_sms_login",
  });

  if (response?.Code !== "OK") {
    throw new Error(response?.Message || "SendSmsVerifyCode failed");
  }

  return {
    biz_id: response?.BizId || "",
    request_id: response?.RequestId || "",
  };
}

async function checkSmsVerifyCode(phone, code, bizId = "") {
  const response = await call("CheckSmsVerifyCode", {
    PhoneNumber: phone,
    VerifyCode: code,
    BizId: bizId,
    OutId: "gaya_sms_login",
  });

  if (response?.Code !== "OK") {
    throw new Error(response?.Message || "CheckSmsVerifyCode failed");
  }

  return {
    verified: response?.VerifyResult === "PASS" || response?.IsPass === "true" || response?.IsPass === true,
    request_id: response?.RequestId || "",
  };
}

module.exports = {
  getMobileByOneTapToken,
  sendSmsVerifyCode,
  checkSmsVerifyCode,
};
