# Build stage
FROM node:14 AS build
WORKDIR /app
COPY package*.json ./
RUN npm install --verbose
COPY . .
RUN npm run build

# Serve stage
FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html

# Copy the entrypoint script into the image
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Set the entrypoint script to be executed
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]