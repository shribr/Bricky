#!/bin/zsh

set -u

device_name="${BRICKY_IOS_DEVICE_NAME:-Ami’s iPhone}"
json_path="${BRICKY_DEVICE_LIST_JSON:-}"
owns_json=false

cleanup() {
    if [[ "$owns_json" == true && -n "$json_path" ]]; then
        rm -f "$json_path"
    fi
}
trap cleanup EXIT

if [[ -z "$json_path" ]]; then
    json_path=$(mktemp)
    owns_json=true
    if ! xcrun devicectl list devices --json-output "$json_path" --quiet; then
        print -u2 "Could not query Xcode's CoreDevice service. Open Xcode once, then retry."
        exit 1
    fi
fi

device_count=$(/usr/bin/plutil -extract result.devices raw "$json_path" 2>/dev/null || print 0)
matched_index=""

for (( index = 0; index < device_count; index++ )); do
    candidate=$(/usr/bin/plutil -extract "result.devices.$index.deviceProperties.name" raw "$json_path" 2>/dev/null || true)
    if [[ "$candidate" == "$device_name" ]]; then
        matched_index="$index"
        break
    fi
done

if [[ -z "$matched_index" ]]; then
    print -u2 "Xcode does not have a paired device named '$device_name'."
    print -u2 "Connect it by USB, unlock it, trust this Mac, and pair it in Xcode > Window > Devices and Simulators."
    exit 2
fi

identifier=$(/usr/bin/plutil -extract "result.devices.$matched_index.identifier" raw "$json_path")
pairing_state=$(/usr/bin/plutil -extract "result.devices.$matched_index.connectionProperties.pairingState" raw "$json_path")
tunnel_state=$(/usr/bin/plutil -extract "result.devices.$matched_index.connectionProperties.tunnelState" raw "$json_path")

print "Device: $device_name"
print "Identifier: $identifier"
print "Pairing: $pairing_state"
print "Connection: $tunnel_state"

case "$tunnel_state" in
    connected)
        print "CoreDevice is connected. Retry the build/install."
        ;;
    connecting)
        print -u2 "The wireless CoreDevice tunnel is stuck connecting."
        print -u2 "Wake and unlock the iPhone. If it does not connect, run the 'iOS: Clear Stale Pairing' task, reconnect by USB, and pair again."
        exit 2
        ;;
    *)
        print -u2 "The paired device is currently unavailable to Xcode."
        print -u2 "Wake and unlock it, verify the same Wi-Fi network, or reconnect it by USB."
        exit 2
        ;;
esac