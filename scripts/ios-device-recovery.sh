#!/bin/zsh

set -u

action="${1:-diagnose}"
device_name="${BRICKY_IOS_DEVICE_NAME:-Ami’s iPhone}"
json_path="${BRICKY_DEVICE_LIST_JSON:-}"
owns_json=false

if [[ "$action" != diagnose && "$action" != clear ]]; then
    print -u2 "Usage: $0 [diagnose|clear]"
    exit 64
fi

run_devicectl() {
    if [[ -n "${BRICKY_DEVICECTL:-}" ]]; then
        "$BRICKY_DEVICECTL" "$@"
    else
        xcrun devicectl "$@"
    fi
}

cleanup() {
    if [[ "$owns_json" == true && -n "$json_path" ]]; then
        rm -f "$json_path"
    fi
}
trap cleanup EXIT

if [[ -z "$json_path" ]]; then
    json_path=$(mktemp)
    owns_json=true
    if ! run_devicectl list devices --json-output "$json_path" --quiet; then
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

if [[ "$action" == clear ]]; then
    if [[ "$tunnel_state" == connected ]]; then
        print -u2 "Refusing to clear a healthy connection. Run this task only when the device is stuck connecting or unavailable."
        exit 3
    fi

    if [[ "$pairing_state" != paired ]]; then
        print -u2 "The device is not currently paired, so there is no stale pairing to clear."
        exit 3
    fi

    if [[ "${BRICKY_CONFIRM_UNPAIR:-}" != YES ]]; then
        print "This will unpair '$device_name' from Xcode. You may need to reconnect it by USB, unlock it, and trust this Mac."
        read "confirmation?Type CLEAR to continue: "
        if [[ "$confirmation" != CLEAR ]]; then
            print "Pairing was not changed."
            exit 4
        fi
    fi

    print "Clearing stale CoreDevice pairing..."
    if ! run_devicectl manage unpair --device "$identifier"; then
        print -u2 "Xcode could not clear the pairing. Open Xcode > Window > Devices and Simulators and unpair the device there."
        exit 1
    fi

    print "Attempting to pair again..."
    if run_devicectl manage pair --device "$identifier"; then
        print "Pairing refreshed. Retry the build/install."
        exit 0
    fi

    print -u2 "The stale pairing was cleared, but the iPhone is not currently discoverable for re-pairing."
    print -u2 "Connect it by USB, unlock it, trust this Mac, then pair it in Xcode > Window > Devices and Simulators."
    exit 2
fi

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