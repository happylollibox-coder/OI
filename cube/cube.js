// Cube configuration options: https://cube.dev/docs/config
const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');

const client = jwksClient({
  jwksUri: 'https://www.googleapis.com/oauth2/v3/certs'
});

function getKey(header, callback) {
  client.getSigningKey(header.kid, function(err, key) {
    if (err) {
      console.error('Error fetching signing key:', err);
      return callback(err, null);
    }
    var signingKey = key.publicKey || key.rsaPublicKey;
    callback(null, signingKey);
  });
}

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
  checkAuth: async (req, auth) => {
    if (!auth) {
      throw new Error('Authentication required');
    }

    return new Promise((resolve, reject) => {
      const decoded = jwt.decode(auth, { complete: true });
      if (!decoded) {
        return reject(new Error('Invalid token'));
      }
      
      // If it's a Google token, verify via JWKS
      if (decoded.header.kid && decoded.payload.iss && decoded.payload.iss.includes('accounts.google.com')) {
        jwt.verify(auth, getKey, {
           audience: process.env.VITE_GOOGLE_CLIENT_ID || '405291422506-9avm18q7kl5kpmoit60l84fpnb1ahg98.apps.googleusercontent.com',
           issuer: ['accounts.google.com', 'https://accounts.google.com']
        }, (err, payload) => {
           if (err) {
             return reject(new Error('Invalid Google token: ' + err.message));
           }
           req.securityContext = { email: payload.email };
           resolve();
        });
      } else {
        // Fallback to local dev secret verification
        const secret = process.env.CUBEJS_API_SECRET || 'dev-secret-key-123';
        jwt.verify(auth, secret, (err, payload) => {
           if (err) {
             return reject(new Error('Invalid dev token'));
           }
           req.securityContext = { email: payload.email || 'local@dev' };
           resolve();
        });
      }
    });
  }
};
