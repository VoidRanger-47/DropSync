FROM node:20-alpine

WORKDIR /app

# Copy all files
COPY . .

# Set environment
ENV NODE_ENV=production
ENV PORT=3000
ENV HOST=0.0.0.0

# Expose port
EXPOSE 3000

# Start relay server
CMD ["node", "server.js"]
