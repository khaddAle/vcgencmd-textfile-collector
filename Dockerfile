FROM debian:trixie-slim

# The key served at archive.raspberrypi.org/.com still has SHA-1 self-signatures,
# which trixie's apt rejects; the keyring package carries the SHA-512 re-signed key.
ARG KEYRING_DEB=raspberrypi-archive-keyring_2025.1+rpt1_all.deb
ARG KEYRING_SHA256=2e727149d7acb8cc7f604e66d0049161039c8aa1eaf1175e54f9e69d963d60e4

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && curl -fsSL -o /tmp/keyring.deb "http://archive.raspberrypi.com/debian/pool/main/r/raspberrypi-archive-keyring/${KEYRING_DEB}" \
 && echo "${KEYRING_SHA256}  /tmp/keyring.deb" | sha256sum -c - \
 && dpkg-deb -x /tmp/keyring.deb /tmp/keyring \
 && cp /tmp/keyring/usr/share/keyrings/raspberrypi-archive-keyring.pgp /usr/share/keyrings/ \
 && rm -rf /tmp/keyring /tmp/keyring.deb \
 && echo "deb [signed-by=/usr/share/keyrings/raspberrypi-archive-keyring.pgp] http://archive.raspberrypi.com/debian/ trixie main" \
      > /etc/apt/sources.list.d/raspi.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends raspi-utils \
 && apt-get purge -y curl && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

COPY collector.sh /usr/local/bin/collector.sh
RUN chmod +x /usr/local/bin/collector.sh

ENTRYPOINT ["/usr/local/bin/collector.sh"]
