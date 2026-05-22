# Cube.js for Cloud Run
# Deployed via: ./deployment/deploy_all.sh cube

FROM cubejs/cube:latest

# Copy schema + config into the Cube.js conf directory
COPY schema /cube/conf/schema
COPY cube.js /cube/conf/cube.js

COPY package.json /cube/conf/package.json

# Install dependencies required for checkAuth (jwks-rsa, jsonwebtoken)
RUN cd /cube/conf && npm install

# Environment variables for BigQuery driver
# Cloud Run uses the default service account — no key file needed
ENV CUBEJS_DB_TYPE=bigquery
ENV CUBEJS_DB_BQ_PROJECT_ID=onyga-482313
ENV CUBEJS_API_SECRET=oi-cube-dev-secret-2026
ENV CUBEJS_DEV_MODE=true
ENV CUBEJS_DB_QUERY_LIMIT=120000
ENV PORT=4000

