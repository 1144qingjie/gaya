const cloudbase = require("@cloudbase/node-sdk");

function app() {
  return cloudbase.init({
    env: process.env.TCB_ENV,
  });
}

function db() {
  return app().database();
}

function auth() {
  return app().auth();
}

module.exports = {
  app,
  db,
  auth,
};
