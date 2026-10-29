FROM alpine:3.19

ENV APP_DIR=/app \
    PORT=5000 \
    PYTHONUNBUFFERED=1

RUN apk update && \
    apk add --no-cache python3 py3-pip && \
    rm -rf /var/cache/apk/*

WORKDIR ${APP_DIR}

COPY requirements.txt .
RUN pip install --no-cache-dir --break-system-packages -r requirements.txt
COPY . .

EXPOSE 5000

CMD ["python3", "app.py"]
