FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY llm_app.py otel_views.py ./
EXPOSE 8000
ENV OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
ENV OTEL_SERVICE_NAME=llm-demo-app
CMD ["uvicorn", "llm_app:app", "--host", "0.0.0.0", "--port", "8000"]
