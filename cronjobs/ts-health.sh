#!/bin/sh

# HEALTHY:
#   latest handshake: 59 seconds ago
#   latest handshake: 1 minute, 59 seconds ago
#   latest handshake: 2 minutes ago
# UNHEALTHY:
#   latest handshake: 2 minutes, 1 second ago
#   latest handshake: 3 minutes ago
#   latest handshake: 3 hours ago

# Cronjob for root (every 5 minutes)
# */5 * * * * /home/umbrel/zap_lnd_tools/cronjobs/ts-health.sh >> /home/umbrel/zap_lnd_tools/logs/wg.log 2>&1
status=$(wg | grep latest)
if echo "$status" | grep -Eq "([2-9]|[1-9][0-9]+) minutes?[, ]" || echo "$status" | grep -q "hour"; then
    current_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$current_time - $status, restarting service..."
    # todo: before restarting the service, run some kind of system query to figure out why wg is not working
    # and log that info so we can inspect it later
    # also: send a telegram alert message that we have restarted the service
    systemctl restart wg-quick@tunnelsatsv2.service
fi