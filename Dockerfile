FROM node:22-slim

# Install openclaw globally
RUN npm install -g openclaw@latest

# Create directories
RUN mkdir -p /root/.openclaw/workspace/memory /data

# Copy config template and setup script
COPY config/openclaw.json /root/.openclaw/openclaw.json
COPY templates/ /app/templates/
COPY setup.sh /app/setup.sh
RUN chmod +x /app/setup.sh

# Workspace is the volume — persists identity, soul, heartbeat, memory
VOLUME ["/root/.openclaw/workspace"]

EXPOSE 18789

# Default: run the gateway headless
ENV OPENCLAW_SKIP_CHANNELS=1
ENV OLLAMA_API_KEY=ollama

ENTRYPOINT ["/app/setup.sh"]
CMD ["gateway"]
