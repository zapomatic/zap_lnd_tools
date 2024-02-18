# LND Tools
LND node tools and configs for an Umbrel LND node.
This repo assumes you are running an Umbrel node with LND. This is built to service the Umbrel zap-o-matic testnet network nodes.

If you are not on an Umbrel node, adjust directories within this project to fit your paths and docker network.


## Install
```
git clone git@github.com:zapomatic/zap_lnd_tools.git /home/umbrel/zap_lnd_tools
cd /home/umbrel/zap_lnd_tools
# add cron jobs
# write out current crontab
sudo crontab -l > sudo.cron
# add new crons into cron file

# run charge-lnd to adjust htlc max every 2 hours (nothing changes if the % range of a channel hasn't changed)
# /home/umbrel/zap_lnd_tools/logs/htlc.log will store the last execution output
echo "35 */2 * * * /home/umbrel/zap_lnd_tools/cronjobs/chargelnd-htlc.sh > /home/umbrel/zap_lnd_tools/logs/htlc.log 2>&1" >> sudo.cron

# install new cron file
sudo crontab sudo.cron
rm sudo.cron
```

## Uninstall

```
sudo crontab -e
```
then remove or comment out cronjobs you don't want