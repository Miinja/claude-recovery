FROM python:3.13-alpine
RUN adduser -D -u 10001 receiver && mkdir -p /data /config && chown receiver /data
COPY app.py /app/app.py
USER receiver
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
CMD ["python", "-u", "/app/app.py"]
