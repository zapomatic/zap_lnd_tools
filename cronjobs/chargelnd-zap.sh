#!/bin/sh
docker run --rm --network=umbrel_main_network -e GRPC_LOCATION=umbrel.local:10009 -e LND_DIR=/data/.lnd -e CONFIG_LOCATION=/app/chargelnd-zap.config -v /home/umbrel/umbrel/app-data/lightning/data/lnd:/data/.lnd  -v /home/umbrel/zap_lnd_tools/apps/charge-lnd:/app zap/charge-lnd:latest
