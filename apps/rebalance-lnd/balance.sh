#!/bin/sh

# Rebalance channels with an emphasis on pushing sats OUT of channels that are low to zero fee
# to all channels that need more outbound liquidity
# unlike lndg rebalance, this script uses rebalance-lnd and balanceofsatoshis to find the best channels
# and it runs through every single pairing to ensure that every option is tried.
# Note that there is no preferential order to which source is used first for a given sink.
# this script was written for the love of testing and is not something you may want to actually run
# unless you really know what you are doing

# additional note: it would perform MUCH faster to write a purpose-built Node.js app using the lightning.proto but 
# rebalance-lnd and bos are already out of the box so I'm not going to bother with that as this is just POC
# a Node.js app could run parallel threads and have reporting/etc (maybe later)

# EDIT CONFIGS BELOW BEFORE RUNNING

# SINKS: channels with high inbound liquidity (75%+)
# SOURCES: channels with high outbound (75%+) + low fee (e.g. under 100 PPM)

# attempt to rebalance from every single SOURCE to every single SINK
# doubling the amount on success until it fails
# WARNING: this does not stop if the route succeeds 
# so it could excessively rebalance a channel in to close to 100%

# example
# sudo ./balance.sh
# or only target a single channel by id
# this will use every SOURCE to rebalance this single target chanid 
# sudo ./balance.sh $TARGET
# note: if you don't require sudo for docker, you can skip the sudo
# and set USER to USER=$(whoami)

TARGET=$1

USER=umbrel # change to your username if not running umbrel

# IF USING UMBREL:
LNDPATH=/home/umbrel/umbrel/app-data/lightning/data/lnd
NETWORK=umbrel_main_network
GRPC=10.21.21.9:10009
# else, set your paths/user/etc appropriately like so:
# LNDPATH=/home/$USER/.lnd
# NETWORK=host
# GRPC=host.docker.internal:10009

BOS_BIN=/home/$USER/.npm-global/bin/bos
BOS_USER=$USER

# NOTE: this variable is used to parse your node vs the partner node from bos
# since the order of the node details is random
MYNODE_NAME=Zap-O-Matic
# docker images are custom built from source 
# (because you shouldn't trust docker images that mount your .lnd directory)
# or use rebalancelnd/rebalance-lnd from docker hub if you want to be trusting, c-otto is probably ok :)
REBALANCE_LND_DOCKER_IMAGE=zap/rebalance-lnd
# what is my max PPM to consider this channel a good push source?
MY_PPM_MAX=1000
# if rebalance succeeds, it will try 2x the amount (until fail)
START_AMOUNT=11111
# cost will be up to 75% of the fee rate for the target sink
FEE_FACTOR=0.65
# only up to a max of 2000 PPM
FEE_PPM_MAX=2500

OUTBOUND_THRESHOLD=70
INBOUND_THRESHOLD=70

# new nodes that have high fees and might have high inbound but
# haven't really found a good starting fee rate yet
# clearly these are just examples:
NEWNODE1=111111111111111111
NEWNODE2=222222222222222222
GSPOT=906394505130934275
CLOSE="912851936929447938"
IGNORE="$NEWNODE1 $NEWNODE2 $GSPOT $CLOSE"

# DRY MODE (DO NOT RUN, ONLY LOG)
# If you didn't read this far, jokes on you :)
DRY_RUN=false

# number of rebalance-lnd -c channels to pluck off for potential sources/sinks
# when testing, initially, set this low, then move it to about 50% of your channel count
SOURCE_COUNT=30
SINK_COUNT=30
##### END CONFIG #####

# we will build up a list of sources below
SOURCES=""

# cache for completed rebalances
COMPLETED=""

# get a single node liquidity info
get_liquidity() {
  docker run --rm --network=$NETWORK -v $LNDPATH:/root/.lnd $REBALANCE_LND_DOCKER_IMAGE --grpc $GRPC -c | grep $1 | while IFS= read -r line; do {
    echo "$line"
  } done
}
get_sinks() {
  docker run --rm --network=$NETWORK -v $LNDPATH:/root/.lnd $REBALANCE_LND_DOCKER_IMAGE --grpc $GRPC -c | tail -n $SINK_COUNT | while IFS= read -r line; do {
    echo "$line"
  } done
}

get_channel_info ()
{
  local output=$(sudo -u $BOS_USER bash -c "$BOS_BIN find '$1' --no-color")
            
# This will return a response like:
# channels:
#   -
#     capacity:         25000000
#     id:               828159x1890x7
#     policies:
#       -
#         alias:            Zap-O-Matic
#         base_fee_mtokens: 0
#         cltv_delta:       80
#         fee_rate:         315
#         is_disabled:      false
#         max_htlc_mtokens: 5420250000
#         min_htlc_mtokens: 1000
#         public_key:       026d0169e8c220d8e789de1e7543f84b9041bbb3e819ab14b9824d37caa94f1eb2
#       -
#         alias:            strike
#         base_fee_mtokens: 0
#         cltv_delta:       80
#         fee_rate:         750
#         is_disabled:      false
#         max_htlc_mtokens: 24750000000
#         min_htlc_mtokens: 10000
#         public_key:       034d7f4bbbd6c1c1d8fbe0a42dd1f59e10b66540c6872dfcaa095d8d5cffebcf46
#     transaction_id:   c4052f6f99eaeca5d6a48dc3e9ccf69cfc1813b8d42800983a81f1487c74d66b
#     transaction_vout: 7
#     updated_at:       2024-03-02T15:08:30.000Z

  local my_ppm=$(echo "$output" | grep -A 7 $MYNODE_NAME | grep 'fee_rate' | awk '{print $2}')
  local my_is_disabled=$(echo "$output" | grep -A 7 $MYNODE_NAME | grep 'is_disabled' | awk '{print $2}')
  local my_base=$(echo "$output" | grep -A 7 $MYNODE_NAME | grep 'base_fee_mtokens' | awk '{print $2}')

  local other_alias=$(echo "$output" | grep -m 2 'alias' | grep -v $MYNODE_NAME | awk '{print $2}')
  local other=$(echo "$output" | grep -A 5 $other_alias)
  local other_ppm=$(echo "$other" | grep 'fee_rate' | awk '{print $2}')
  local other_is_disabled=$(echo "$other" |grep 'is_disabled' | awk '{print $2}')
  local other_base=$(echo "$other" | grep 'base_fee_mtokens' | awk '{print $2}')
  local transaction_vout=$(echo "$other" | grep 'transaction_vout' | awk '{print $2}')
  echo "$my_ppm $my_is_disabled $my_base $other_alias $other_ppm $other_is_disabled $other_base $transaction_vout" 
}

try_rebalance()
{
  local from=""
  local to=""
  local ppm=""
  local amt=""
  local percent=""
  local feefactor=""

  if [ ! -z "$1" ]; then
    from="-f $1"
  fi
  if [ ! -z "$2" ]; then
    to="-t $2"
  fi
  if [ ! -z "$3" ]; then
    ppm="--fee-ppm-limit $3"
  fi
  if [ ! -z "$4" ]; then
    amt="-a $4"
  fi
  if [ ! -z "$5" ]; then
    percent="-p $5"
  fi
  if [ ! -z "$6" ]; then
    feefactor="--fee-factor $6"
  fi
  docker run --rm --network=$NETWORK -v $LNDPATH:/root/.lnd $REBALANCE_LND_DOCKER_IMAGE --grpc $GRPC --min-amount 100 --ignore-missed-fee $from $to $ppm $amt $percent $feefactor | while IFS= read -r line; do {
    # if echo "$line" | grep -q "Trying "; then
    #   echo "\t$line"
    # fi
    # if echo "$line" | grep -q "Using "; then
    #   echo $line
    # fi
    if echo "$line" | grep -q "Sending "; then
      echo "➡️  $line"
    elif echo "$line" | grep -q "Increased"; then
      echo $line
    elif echo "$line" | grep -q "Fee:"; then
      echo $line
      if [ -n "$4" ]; then
        amount=$(($4 * 2))
        echo "✅ Rebalance successful, checking liquidity"
        chaninfo=$(get_liquidity $2)
        outbound=$(echo "$chaninfo" | awk -F '|' '{print $2}' | tr -cd '[:digit:]' | awk '{$1=$1};1')
        inbound=$(echo "$chaninfo" | awk -F '|' '{print $3}' | tr -cd '[:digit:]' | awk '{$1=$1};1')
        name=$(echo "$chaninfo" | awk -F '|' '{print $4}' | awk '{$1=$1};1')

        capacity=$((inbound + outbound))

        # too much inbound? potential target...
        if [ "$((inbound * 100))" -lt "$((INBOUND_THRESHOLD * capacity))" ]; then
          echo "🚫 not retrying target: $name because it now has less than $INBOUND_THRESHOLD% inbound"
          COMPLETED="$COMPLETED $2"
          continue
        fi
 
        amount=$(($4 * 2))
        echo "✅ $name:$2 still has too much inbound. Retrying with $amount"
        try_rebalance "$1" "$2" "$3" "$amount" "$5" "$6"
      elif [ -n "$5" ]; then
        percent=$(($5 - 1))
        echo "✅ Rebalance successful at $5%, retrying with $percent%"
        try_rebalance "$1" "$2" "$3" "$4" "$percent" "$6"
      fi
    fi
    
  } done
}

try_rebalance_series() (
  targetid="$1"
  name="$2"
  echo "⚡️ Attempting to send $START_AMOUNT sats at max $FEE_PPM_MAX PPM up to $FEE_FACTOR of cost into $name ($targetid) from each source"
  for sourceId in $SOURCES; do
    if [ "$DRY_RUN" = "true" ]; then
      echo "🔍 dry run: $sourceId -> $targetid"
      continue
    fi
    if [ -n "$COMPLETED" ]; then
      if echo "$COMPLETED" | grep -q "$targetid"; then
        echo "🕐 ignore rebalancing to $targetid because it is on COMPLETED list"
        continue
      fi
    fi
    # make sure the source still has too much outbound
    chaninfo=$(get_liquidity $sourceId)
    outbound=$(echo "$chaninfo" | awk -F '|' '{print $2}' | tr -cd '[:digit:]' | awk '{$1=$1};1')
    inbound=$(echo "$chaninfo" | awk -F '|' '{print $3}' | tr -cd '[:digit:]' | awk '{$1=$1};1')
    name=$(echo "$chaninfo" | awk -F '|' '{print $4}' | awk '{$1=$1};1')

    capacity=$((inbound + outbound))

    # not enough outbound anymore?
  if [ "$((outbound * 100))" -lt "$((OUTBOUND_THRESHOLD * capacity))" ]; then
      echo "🚫 not using $sourceId ($name) as a source any longer because it now has less than $OUTBOUND_THRESHOLD% outbound"
      SOURCES=$(echo "$SOURCES" | sed "s/$sourceId//")
      continue
    fi

    try_rebalance $sourceId $targetid $FEE_PPM_MAX $START_AMOUNT "" $FEE_FACTOR
  done
)



echo "🔬 analyzing highest $SOURCE_COUNT outbound channels to feed sinks... (note that using '| head -n $SOURCE_COUNT' here is known to throw 'write /dev/stdout: broken pipe'). Please PR a fix, as I am too lazy."
potential_sources=$(docker run --rm --network=$NETWORK -v $LNDPATH:/root/.lnd $REBALANCE_LND_DOCKER_IMAGE --grpc $GRPC -c | head -n $SOURCE_COUNT)

# NOTE, using echo | while creates a subshell that can't write to SOURCES
# also we can't use <<< redirection in /bin/sh
# so even though I wouldn't normally use the EOF approach, here is a funky way of doing it without abusing the filesystem, 
# but it works: meh :shrug:
while IFS= read -r line; do
  
  # echo "$line"
  chanid=$(echo "$line" | awk -F '|' '{print $1}' | awk '{$1=$1};1')
  outbound=$(echo "$line" | awk -F '|' '{print $2}' | tr -cd '[:digit:]' | awk '{$1=$1};1')
  inbound=$(echo "$line" | awk -F '|' '{print $3}' | tr -cd '[:digit:]' | awk '{$1=$1};1')
  name=$(echo "$line" | awk -F '|' '{print $4}' | awk '{$1=$1};1')

  capacity=$((inbound + outbound))
  outbound_percent=$((100 * outbound / capacity))

  # any channel with $OUTBOUND_THRESHOLD%+ outbound is a potential source
  if [ "$((outbound * 100))" -lt "$((OUTBOUND_THRESHOLD * capacity))" ]; then
    echo "🚫 source: $chanid:$name as source because it has less than $OUTBOUND_THRESHOLD% outbound"
    continue;
  fi

  channel_info=$(get_channel_info "$chanid")
  my_ppm=$(echo "$channel_info" | awk '{print $1}')
  my_is_disabled=$(echo "$channel_info" | awk '{print $2}')
  my_base=$(echo "$channel_info" | awk '{print $3}')
  other_alias=$(echo "$channel_info" | awk '{print $4}')
  other_ppm=$(echo "$channel_info" | awk '{print $5}')
  other_is_disabled=$(echo "$channel_info" | awk '{print $6}')
  other_base=$(echo "$channel_info" | awk '{print $7}')


  if [ "$my_is_disabled" = "true" ]; then
    echo "🚫 source: $chanid:$other_alias because it is disabled by me (cannot send funds)"
    continue
  fi

  if [ "$my_ppm" -gt "$MY_PPM_MAX" ]; then
    echo "🚫 source: $chanid:$other_alias because our fee is $my_ppm PPM + $my_base"
    continue
  fi
  echo "⬆️  source: $chanid:$other_alias with $my_ppm PPM + $my_base and $outbound_percent% outbound"

  # add this source chanid to the global SOURCES list
  if [ -z "$SOURCES" ]; then
    SOURCES="$chanid"
  else
    SOURCES="$SOURCES $chanid"
  fi
done <<EOF
$potential_sources
EOF

if [ -n "$TARGET" ]; then
  echo "using only single target of $TARGET"
  try_rebalance_series $TARGET ""
  exit 0;
fi

echo "🔬 analyzing highest $SINK_COUNT inbound channel sinks to fill with sources ($SOURCES)...  (note that using '| tail -n $SINK_COUNT' here is known to throw 'write /dev/stdout: broken pipe'). Please PR a fix, as I am too lazy."  
potential_sinks=$(docker run --rm --network=$NETWORK -v $LNDPATH:/root/.lnd $REBALANCE_LND_DOCKER_IMAGE --grpc $GRPC -c | tail -n $SINK_COUNT)

while IFS= read -r line; do
  targetid=$(echo "$line" | awk -F '|' '{print $1}' | awk '{$1=$1};1')
  outbound=$(echo "$line" | awk -F '|' '{print $2}' | tr -cd '[:digit:]' | awk '{$1=$1};1')
  inbound=$(echo "$line" | awk -F '|' '{print $3}' | tr -cd '[:digit:]' | awk '{$1=$1};1')
  name=$(echo "$line" | awk -F '|' '{print $4}' | awk '{$1=$1};1')

  capacity=$((inbound + outbound))

  # too much inbound? potential target...
  if [ "$((inbound * 100))" -lt "$((INBOUND_THRESHOLD * capacity))" ]; then
    echo "🚫 target: $name because it has less than $INBOUND_THRESHOLD% inbound"
    continue
  fi

  if echo "$IGNORE" | grep -q "$targetid"; then
    echo "🕐 ignore rebalancing to $targetid because it is on IGNORE list"
    continue
  fi

  channel_info=$(get_channel_info "$targetid")
  my_ppm=$(echo "$channel_info" | awk '{print $1}')
  my_is_disabled=$(echo "$channel_info" | awk '{print $2}')
  my_base=$(echo "$channel_info" | awk '{print $3}')
  other_alias=$(echo "$channel_info" | awk '{print $4}')
  other_ppm=$(echo "$channel_info" | awk '{print $5}')
  other_is_disabled=$(echo "$channel_info" | awk '{print $6}')
  other_base=$(echo "$channel_info" | awk '{print $7}')
  transaction_vout=$(echo "$channel_info" | awk '{print $8}')
  

  if [ "$other_is_disabled" = "true" ]; then
    echo "🚫 target: $targetid:$other_alias because it is disabled by peer (cannot receive funds)"
    continue
  fi

  # don't even try to rebalance a channel if their fee is higher than ours
  if [ "$my_ppm" -lt "$other_ppm" ]; then
    echo "🚫 target: $targetid:$other_alias because it has a higher fee ($other_ppm PPM + $other_base) than we have ($my_ppm PPM + $my_base)"
    continue
  fi

  try_rebalance_series $targetid "$name"
done <<EOF
$potential_sinks
EOF
