FROM alpine:3.19

RUN apk add --no-cache python3 py3-pip nodejs npm git && \
    rm -rf /var/cache/apk/*

RUN pip install --no-cache-dir --break-system-packages flake8==7.1.0 pylint==3.2.0
RUN npm install -g eslint@9 @eslint/js globals --silent

WORKDIR /code

COPY .flake8 /code/.flake8
COPY eslint.config.mjs /code/eslint.config.mjs
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
