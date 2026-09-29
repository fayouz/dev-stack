FROM restic/restic:latest

RUN apk add --no-cache bash curl jq mariadb-client tzdata

COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]
