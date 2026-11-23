FROM python:3.12-slim
WORKDIR /app
COPY tools/server/ /app/server/
COPY data/ /app/data/
RUN pip install --no-cache-dir -r /app/server/requirements.txt
ENV ELITE_DATA=/app/data ELITE_DB=/var/lib/elite/elite.db ELITE_HOST=0.0.0.0 ELITE_PORT=8765
VOLUME /var/lib/elite
EXPOSE 8765
CMD ["python3", "/app/server/elite_server.py"]
