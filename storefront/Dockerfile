FROM node:21-alpine as builder

WORKDIR /app/storefront

COPY . . 

RUN rm -rf node_modules \
 && yarn global add gatsby-cli \
 && yarn add sharp \
 && yarn install \
 && gatsby build

FROM nginx:1.25-alpine

EXPOSE 80

COPY --from=builder /app/storefront/public /usr/share/nginx/html

ENTRYPOINT ["nginx", "-g", "daemon off;"]