FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY collectors/ ./collectors/
COPY common/ ./common/
COPY blob_uploader/ ./blob_uploader/
RUN mkdir -p /app/data
ENV PYTHONUNBUFFERED=1
