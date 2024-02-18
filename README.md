# LND Tools
LND node tools and configs for an Umbrel LND node.
This repo assumes you are running an Umbrel node with LND. This is built to service the Umbrel [Zap-O-Matic](https://amboss.space/node/026d0169e8c220d8e789de1e7543f84b9041bbb3e819ab14b9824d37caa94f1eb2) testnet network nodes.

If you are not on an Umbrel node, adjust directories within this project to fit your paths and docker network.

This repo will grow as more tools are solidified outside of the testnet cluster. Some tools may be beta. Please review before using.

## Install
```
git clone https://github.com/zapomatic/zap_lnd_tools.git /home/umbrel/zap_lnd_tools
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


## Additional Tools

Check out https://github.com/jvxis/nr-tools run by [Friendspool⚡🍻](https://amboss.space/node/023e24602891c28a7872ea1ad5c1bb41abe4206ae1599bb981e3278a121e7895d6)