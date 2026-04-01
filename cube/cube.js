// Cube configuration options: https://cube.dev/docs/config
/** @type{ import('@cubejs-backend/server-core').CreateOptions } */
module.exports = {
  schemaPath: 'schema',
  http: {
    cors: {
      origin: '*',
      methods: 'GET,HEAD,PUT,PATCH,POST,DELETE',
      preflightContinue: false,
      optionsSuccessStatus: 204,
      credentials: true,
      allowedHeaders: ['Content-Type', 'Authorization'],
    },
  },
  orchestratorOptions: {
    continueWaitTimeout: 90,
    queryCacheOptions: {
      refreshKeyRenewalThreshold: 300,
    },
  },
};
