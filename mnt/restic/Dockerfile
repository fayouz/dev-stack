FROM restic/restic:0.19.1

RUN apk add --no-cache bash curl jq mariadb-client tzdata

COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]
