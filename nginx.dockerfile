#FROM node:latest
FROM nginx:latest
#COPY --from=builder /build /var/www/html
COPY nginx.conf /etc/nginx/nginx.conf
COPY default.conf /etc/nginx/sites-enabled/default.conf
