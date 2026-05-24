FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates gnupg \
 && curl -fsSL https://archive.raspberrypi.org/debian/raspberrypi.gpg.key \
      | gpg --dearmor > /usr/share/keyrings/raspberrypi.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/raspberrypi.gpg] http://archive.raspberrypi.com/debian/ bookworm main" \
      > /etc/apt/sources.list.d/raspi.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends raspi-utils \
 && apt-get purge -y curl gnupg && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

COPY collector.sh /usr/local/bin/collector.sh
RUN chmod +x /usr/local/bin/collector.sh

ENTRYPOINT ["/usr/local/bin/collector.sh"]
