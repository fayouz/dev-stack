#!/usr/bin/env bash
# Certificats HTTPS de la dev-stack. Usage : make certs
#
# - Autorité de certification locale RESTREINTE au domaine de la stack (contrainte
#   de nom X.509) : même si sa clé fuitait, elle ne pourrait signer aucun autre site.
#   Créée une seule fois (mnt/certs/ca/), valable 10 ans. Son certificat ca.crt est à
#   installer une fois dans le magasin « Autorités de certification racines de
#   confiance » de Windows (et de WSL pour curl).
# - Certificat serveur *.DOMAIN signé par cette autorité (mnt/certs/server/), le seul
#   monté dans Traefik. Réémis s'il manque ou expire dans moins de 30 jours.
# Rien n'est versionné : chaque machine génère ses propres certificats.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DOMAIN=${DOMAIN:-$(grep '^DOMAIN=' "$ROOT/.env" | cut -d= -f2-)}
CA_DIR="$ROOT/mnt/certs/ca"
SERVER_DIR="$ROOT/mnt/certs/server"
mkdir -p "$CA_DIR" "$SERVER_DIR"
umask 077

if [ ! -f "$CA_DIR/ca.key" ]; then
    echo "Création de l'autorité de certification (restreinte à $DOMAIN)"
    openssl req -x509 -new -nodes -newkey rsa:3072 -sha256 -days 3650 \
        -keyout "$CA_DIR/ca.key" -out "$CA_DIR/ca.crt" \
        -subj "/O=docker-master/CN=docker-master dev CA ($DOMAIN)" \
        -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" \
        -addext "nameConstraints=critical,permitted;DNS:$DOMAIN" 2>/dev/null
    chmod 644 "$CA_DIR/ca.crt"
fi

if [ -f "$SERVER_DIR/server.crt" ] && openssl x509 -checkend $((30 * 86400)) -noout -in "$SERVER_DIR/server.crt" >/dev/null; then
    echo "Certificat serveur *.$DOMAIN encore valable : $(openssl x509 -enddate -noout -in "$SERVER_DIR/server.crt" | cut -d= -f2)"
else
    echo "Émission du certificat serveur *.$DOMAIN"
    openssl req -new -nodes -newkey rsa:2048 -keyout "$SERVER_DIR/server.key" \
        -out "$SERVER_DIR/server.csr" -subj "/CN=*.$DOMAIN" 2>/dev/null
    openssl x509 -req -in "$SERVER_DIR/server.csr" -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" \
        -CAcreateserial -days 825 -sha256 -out "$SERVER_DIR/server.crt" -extfile <(printf '%s\n' \
            "subjectAltName=DNS:*.$DOMAIN,DNS:$DOMAIN" \
            "basicConstraints=critical,CA:FALSE" \
            "keyUsage=critical,digitalSignature,keyEncipherment" \
            "extendedKeyUsage=serverAuth") 2>/dev/null
    rm -f "$SERVER_DIR/server.csr"
    # Lisibles par Traefik (le dossier serveur ne contient pas la clé de l'autorité)
    chmod 644 "$SERVER_DIR/server.crt" "$SERVER_DIR/server.key"
fi

openssl verify -CAfile "$CA_DIR/ca.crt" "$SERVER_DIR/server.crt"
echo "Autorité à installer dans Windows : $CA_DIR/ca.crt"
