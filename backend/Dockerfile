FROM node:21-alpine as builder

WORKDIR /app/medusa

COPY . . 

RUN rm -rf node_modules \
 && npm install -g npm@latest \
 && npm install --loglevel=error \
 && npm run build

FROM node:21-alpine

ENV CERT_HOME=/usr/local/share/ca-certificates
RUN mkdir -p ${CERT_HOME} \
 && wget -O ${CERT_HOME}/extra-ca.crt https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
# && npm config set cafile ${CERT_HOME}/extra-ca.crt
ENV NODE_EXTRA_CA_CERTS=${CERT_HOME}/extra-ca.crt

WORKDIR /app/medusa

COPY medusa-start.sh .

RUN mkdir dist \
 && chmod +x medusa-start.sh

COPY package*.json ./ 

COPY medusa-config.js .

RUN npm install -g @medusajs/medusa-cli

RUN npm i --omit=dev

COPY --from=builder /app/medusa/dist ./dist

EXPOSE 9000

ENTRYPOINT ["/app/medusa/medusa-start.sh", "start"]