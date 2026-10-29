FROM alpine:3.19

RUN apk add --no-cache python3 py3-pip && \
    rm -rf /var/cache/apk/*

RUN pip install --no-cache-dir --break-system-packages \
    pytest==8.2.0 \
    requests==2.32.3 \
    pytest-html==4.1.1

WORKDIR /tests

COPY test_api.py .

ENV API_URL=http://backend:5000 \
    REPORT=0

CMD ["sh", "-c", "if [ \"$REPORT\" = \"1\" ]; then pytest test_api.py -v --html=/tests/report.html --self-contained-html; else pytest test_api.py -v; fi"]
