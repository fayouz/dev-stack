FROM aquasec/trivy:0.75.0

RUN apk add --no-cache bash curl jq tzdata

COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]
