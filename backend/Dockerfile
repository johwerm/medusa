FROM node:21-alpine

WORKDIR /usr/src/app

COPY package.json .
RUN npm install 
COPY . .

ENV CERT_HOME=/usr/local/share/ca-certificates
RUN mkdir -p ${CERT_HOME} \
 && wget -O ${CERT_HOME}/extra-ca.crt https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem

ENV NODE_EXTRA_CA_CERTS=${CERT_HOME}/extra-ca.crt
 
# && npm config set cafile ${CERT_HOME}/extra-ca.crt
# && apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
# && TOKEN="$(aws rds generate-db-auth-token --hostname the_host --port 3306 --region eu-west-1 --username db_user)" \
# && mysql -h the_host --port=3306 --ssl-ca=rds-combined-ca-bundle.pem --enable-cleartext-plugin -u db_user --password=$TOKEN"

EXPOSE 80

ENTRYPOINT ["npm", "run", "start"]
