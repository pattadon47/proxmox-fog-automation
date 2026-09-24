# FOG master update and capture pipeline for Proxmox node itopplus
# Install as /root/auto_capture.sh and keep secrets in /root/fog_automation.env

set -Eeuo pipefail
umask 077

LOCK_FILE="/run/lock/fog-auto-capture.lock"
ENV_FILE="/root/fog_automation.env"

FOG_VMID="100"
MINT_VMID="101"
MINT_HOST_ID="1"
UBUNTU_VMID="103"
UBUNTU_HOST_ID="3"
WINDOWS_VMID="102"
WINDOWS_HOST_ID="5"

# Fixed two-slot image rotation. The first run overwrites the older/empty slot:
# Mint A (19), Ubuntu A (20), and Windows B (24).
MINT_IMAGE_A_ID="19"
MINT_IMAGE_B_ID="21"
UBUNTU_IMAGE_A_ID="20"
UBUNTU_IMAGE_B_ID="22"
WINDOWS_IMAGE_A_ID="17"
WINDOWS_IMAGE_B_ID="24"
SLOT_STATE_DIR="/var/lib/fog-auto-capture"

NAS_IP="172.16.10.113"
FOG_READY_TIMEOUT=600
GUEST_AGENT_TIMEOUT=600
UPDATE_TIMEOUT=7200
CAPTURE_TIMEOUT=14400
SHUTDOWN_TIMEOUT=300
WINDOWS_UPDATE_PASSES=4

START_EPOCH=$(date +%s)
RESULTS=()
NEW_MINT_IMAGE="pending"
NEW_UBUNTU_IMAGE="pending"
NEW_WIN_IMAGE="pending"
MINT_STATUS="pending"
UBUNTU_STATUS="pending"
WIN_STATUS="pending"

log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*"
}

die() {
    log "ERROR: $*"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

if [[ $EUID -ne 0 ]]; then
    die "Run this script as root"
fi

[[ -r "$ENV_FILE" ]] || die "Missing $ENV_FILE"
# shellcheck source=/dev/null
source "$ENV_FILE"

: "${FOG_IP:?Set FOG_IP in $ENV_FILE}"
: "${FOG_API_TOKEN:?Set FOG_API_TOKEN in $ENV_FILE}"
: "${FOG_USER_TOKEN:?Set FOG_USER_TOKEN in $ENV_FILE}"

for cmd in curl flock grep ip jq ping qm; do
    require_command "$cmd"
done

exec 9>"$LOCK_FILE"
flock -n 9 || die "Another auto_capture.sh process is already running"

PROXMOX_IP=$(ip -4 -o addr show dev vmbr0 2>/dev/null |
    awk '{split($4,a,"/"); print a[1]; exit}')
if [[ -z "$PROXMOX_IP" ]]; then
    PROXMOX_IP=$(hostname -I | awk '{print $1}')
fi

fog_api() {
    local method=$1
    local endpoint=$2
    local data=${3:-}
    local args=(
        --silent --show-error --fail-with-body
        --connect-timeout 10 --max-time 90
        -X "$method"
        -H "fog-api-token: $FOG_API_TOKEN"
        -H "fog-user-token: $FOG_USER_TOKEN"
    )

    if [[ -n "$data" ]]; then
        args+=(-H "Content-Type: application/json" -d "$data")
    fi

    curl "${args[@]}" "http://${FOG_IP}/fog/${endpoint#/}"
}

send_line() {
    local message=$1
    [[ -n "${LINE_TOKEN:-}" && -n "${LINE_GROUP_ID:-}" ]] || return 0

    local payload
    payload=$(jq -nc \
        --arg to "$LINE_GROUP_ID" \
        --arg text "$message" \
        '{to:$to,messages:[{type:"text",text:$text}]}')

    curl --silent --show-error --fail-with-body \
        --connect-timeout 10 --max-time 30 \
        -X POST 'https://api.line.me/v2/bot/message/push' \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $LINE_TOKEN" \
        -d "$payload" >/dev/null || log "WARNING: LINE notification failed"
}

send_line_flex_success() {
    [[ -n "${LINE_TOKEN:-}" && -n "${LINE_GROUP_ID:-}" ]] || return 0

    local elapsed finish_time payload
    elapsed=$(( $(date +%s) - START_EPOCH ))
    finish_time=$(date '+%H:%M:%S')

    payload=$(jq -nc \
        --arg to "$LINE_GROUP_ID" \
        --arg finish "$finish_time" \
        --arg host "$PROXMOX_IP" \
        --arg duration "$((elapsed / 60)) นาที $((elapsed % 60)) วินาที" \
        --arg mint_image "$NEW_MINT_IMAGE" \
        --arg mint_status "$MINT_STATUS" \
        --arg ubuntu_image "$NEW_UBUNTU_IMAGE" \
        --arg ubuntu_status "$UBUNTU_STATUS" \
        --arg win_image "$NEW_WIN_IMAGE" \
        --arg win_status "$WIN_STATUS" \
        '{
          to:$to,
          messages:[{
            type:"flex",
            altText:"อัปเดต OS และ Capture FOG สำเร็จ",
            contents:{
              type:"bubble",size:"giga",
              header:{type:"box",layout:"vertical",backgroundColor:"#0F172A",
                paddingTop:"18px",paddingBottom:"18px",contents:[
                  {type:"text",text:("● สำเร็จ " + $finish + " น."),color:"#10B981",weight:"bold",size:"xs"},
                  {type:"text",text:"อัปเดต OS และ Capture สำเร็จ",weight:"bold",size:"md",color:"#F8FAFC",margin:"xs"},
                  {type:"text",text:("Proxmox " + $host + " · " + $duration),size:"xs",color:"#38BDF8",margin:"xs"}
                ]},
              body:{type:"box",layout:"vertical",backgroundColor:"#020617",spacing:"md",paddingAll:"16px",contents:[
                {type:"box",layout:"vertical",backgroundColor:"#0F172A",cornerRadius:"8px",paddingAll:"12px",contents:[
                  {type:"text",text:"🐧 Linux Mint",weight:"bold",size:"sm",color:"#38BDF8"},
                  {type:"text",text:("Image: " + $mint_image),size:"xs",color:"#94A3B8",margin:"xs",wrap:true},
                  {type:"text",text:$mint_status,size:"xs",color:"#10B981",margin:"xs",weight:"bold"}
                ]},
                {type:"box",layout:"vertical",backgroundColor:"#0F172A",cornerRadius:"8px",paddingAll:"12px",contents:[
                  {type:"text",text:"🟠 Ubuntu",weight:"bold",size:"sm",color:"#FB923C"},
                  {type:"text",text:("Image: " + $ubuntu_image),size:"xs",color:"#94A3B8",margin:"xs",wrap:true},
                  {type:"text",text:$ubuntu_status,size:"xs",color:"#10B981",margin:"xs",weight:"bold"}
                ]},
                {type:"box",layout:"vertical",backgroundColor:"#0F172A",cornerRadius:"8px",paddingAll:"12px",contents:[
                  {type:"text",text:"🪟 Windows",weight:"bold",size:"sm",color:"#60A5FA"},
                  {type:"text",text:("Image: " + $win_image),size:"xs",color:"#94A3B8",margin:"xs",wrap:true},
                  {type:"text",text:$win_status,size:"xs",color:"#10B981",margin:"xs",weight:"bold"}
                ]}
              ]}
            }
          }]
        }')

    curl --silent --show-error --fail-with-body \
        --connect-timeout 10 --max-time 30 \
        -X POST 'https://api.line.me/v2/bot/message/push' \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $LINE_TOKEN" \
        -d "$payload" >/dev/null || log "WARNING: LINE Flex notification failed"
}

vm_state() {
    qm status "$1" | awk '{print $2}'
}

wait_vm_state() {
    local vmid=$1
    local expected=$2
    local timeout_seconds=$3
    local started=$SECONDS

    while [[ "$(vm_state "$vmid")" != "$expected" ]]; do
        if (( SECONDS - started >= timeout_seconds )); then
            return 1
        fi
        sleep 5
    done
}

ensure_vm_running() {
    local vmid=$1
    if [[ "$(vm_state "$vmid")" != "running" ]]; then
        log "Starting VM $vmid"
        qm start "$vmid"
    fi
}

wait_guest_agent() {
    local vmid=$1
    local started=$SECONDS

    until qm guest cmd "$vmid" ping >/dev/null 2>&1; do
        if (( SECONDS - started >= GUEST_AGENT_TIMEOUT )); then
            return 1
        fi
        sleep 5
    done
}

shutdown_vm() {
    local vmid=$1
    log "Shutting down VM $vmid"
    qm shutdown "$vmid" --timeout "$SHUTDOWN_TIMEOUT"
    wait_vm_state "$vmid" stopped "$SHUTDOWN_TIMEOUT" ||
        die "VM $vmid did not shut down; inspect it manually"
}

fog_host_has_active_task() {
    local host_id=$1
    local json
    json=$(fog_api GET task/active)
    jq -e --arg host_id "$host_id" '
        .. | objects |
        select((((.hostID? // .hostId? // "") | tostring) == $host_id))
    ' <<<"$json" >/dev/null
}

fog_has_any_active_task() {
    local json
    json=$(fog_api GET task/active)
    jq -e '
        .. | objects |
        select(has("hostID") or has("hostId") or has("taskTypeID"))
    ' <<<"$json" >/dev/null
}

wait_fog_ready() {
    local started=$SECONDS
    until curl --silent --fail --connect-timeout 5 --max-time 15 \
        "http://${FOG_IP}/fog/" >/dev/null; do
        if (( SECONDS - started >= FOG_READY_TIMEOUT )); then
            return 1
        fi
        sleep 5
    done
}

wait_capture_finished() {
    local vmid=$1
    local host_id=$2
    local started=$SECONDS

    while fog_host_has_active_task "$host_id" ||
        [[ "$(vm_state "$vmid")" != "stopped" ]]; do
        if (( SECONDS - started >= CAPTURE_TIMEOUT )); then
            return 1
        fi
        sleep 20
    done
}

schedule_capture() {
    local vmid=$1
    local host_id=$2
    local image_id=$3
    local image_name=$4
    local disk_boot=$5
    local host_payload

    fog_api GET "image/${image_id}" >/dev/null ||
        die "FOG Image ID $image_id ($image_name) does not exist"
    host_payload=$(jq -nc --argjson image_id "$image_id" \
        '{imageID:$image_id}')

    log "Assigning Image $image_name to FOG Host ID $host_id"
    fog_api PUT "host/${host_id}/edit" "$host_payload" >/dev/null
    fog_api POST "host/${host_id}/task" \
        '{"taskTypeID":2,"shutdown":true}' >/dev/null

    qm set "$vmid" --boot "order=net1;${disk_boot}"
    qm start "$vmid"

    wait_capture_finished "$vmid" "$host_id" ||
        die "Capture timed out for VM $vmid / FOG Host $host_id"

    qm set "$vmid" --boot "order=${disk_boot}"
    RESULTS+=("${image_name}: task finished; verify History, size and NAS files")
    log "Capture task finished for $image_name"
}

capture_next_slot() {
    local vmid=$1
    local host_id=$2
    local key=$3
    local default_last_slot=$4
    local image_a_id=$5
    local image_b_id=$6
    local image_prefix=$7
    local disk_boot=$8
    local state_file="${SLOT_STATE_DIR}/${key}.slot"
    local last_slot next_slot image_id image_name temp_state

    last_slot=$(tr -d '[:space:]' <"$state_file" 2>/dev/null || true)
    if [[ "$last_slot" != "A" && "$last_slot" != "B" ]]; then
        last_slot=$default_last_slot
    fi

    if [[ "$last_slot" == "A" ]]; then
        next_slot="B"
        image_id=$image_b_id
    else
        next_slot="A"
        image_id=$image_a_id
    fi
    image_name="${image_prefix}-${next_slot}"

    case "$key" in
        mint) NEW_MINT_IMAGE=$image_name ;;
        ubuntu) NEW_UBUNTU_IMAGE=$image_name ;;
        windows) NEW_WIN_IMAGE=$image_name ;;
    esac

    log "$image_prefix: last successful slot=$last_slot; capturing to slot=$next_slot (Image ID $image_id)"
    schedule_capture "$vmid" "$host_id" "$image_id" "$image_name" "$disk_boot"

    temp_state="${state_file}.tmp"
    printf '%s\n' "$next_slot" >"$temp_state"
    mv -f "$temp_state" "$state_file"

    case "$key" in
        mint) MINT_STATUS="อัปเดตและ Capture สำเร็จ" ;;
        ubuntu) UBUNTU_STATUS="อัปเดตและ Capture สำเร็จ" ;;
        windows) WIN_STATUS="อัปเดตและ Capture สำเร็จ" ;;
    esac
}

update_linux() {
    local vmid=$1
    local label=$2

    ensure_vm_running "$vmid"
    wait_guest_agent "$vmid" || die "$label Guest Agent timed out"

    log "Updating $label on VM $vmid"
    qm guest exec "$vmid" --timeout "$UPDATE_TIMEOUT" -- \
        /bin/bash -lc \
        'export DEBIAN_FRONTEND=noninteractive;
         apt-get update &&
         apt-get -y dist-upgrade &&
         apt-get -y autoremove'

    log "Rebooting $label once to test the updated operating system"
    qm reboot "$vmid"
    sleep 20
    wait_guest_agent "$vmid" || die "$label did not return after reboot"

    log "Preparing $label identity for cloning"
    qm guest exec "$vmid" --timeout 120 -- \
        /bin/bash -lc \
        'set -e;
         apt-get clean;
         rm -f /var/lib/clone-hostname-set;
         truncate -s 0 /etc/machine-id;
         rm -f /var/lib/dbus/machine-id;
         ln -s /etc/machine-id /var/lib/dbus/machine-id;
         sync'

    shutdown_vm "$vmid"
}

update_windows() {
    local windows_update_ps update_output pass update_clean=0

    ensure_vm_running "$WINDOWS_VMID"
    wait_guest_agent "$WINDOWS_VMID" || die "Windows Guest Agent timed out"

    log "Enabling a system-managed Windows pagefile"
    qm guest exec "$WINDOWS_VMID" --timeout 120 -- \
        powershell.exe -NoProfile -NonInteractive \
        -ExecutionPolicy Bypass -Command \
        '$system = Get-CimInstance Win32_ComputerSystem;
         Set-CimInstance -InputObject $system -Property @{AutomaticManagedPagefile = $true} | Out-Null'

    log "Rebooting Windows so the pagefile setting is active"
    qm reboot "$WINDOWS_VMID"
    sleep 30
    wait_guest_agent "$WINDOWS_VMID" ||
        die "Windows did not return after the pagefile reboot"
    sleep 30

    windows_update_ps=$(cat <<'POWERSHELL'
$ErrorActionPreference = 'Stop'
$session = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()
$result = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
$updates = New-Object -ComObject Microsoft.Update.UpdateColl
foreach ($update in $result.Updates) {
    if (-not $update.EulaAccepted) { $update.AcceptEula() }
    if (-not $update.InstallationBehavior.CanRequestUserInput) {
        [void]$updates.Add($update)
    }
}
if ($updates.Count -eq 0) {
    Write-Output 'FOG_UPDATE_STATE=NO_UPDATES'
    exit 0
}
$downloader = $session.CreateUpdateDownloader()
$downloader.Updates = $updates
$downloadResult = $downloader.Download()
if ($downloadResult.ResultCode -notin 2,3) {
    throw "Windows Update download failed: $($downloadResult.ResultCode)"
}
$installer = $session.CreateUpdateInstaller()
$installer.Updates = $updates
$installResult = $installer.Install()
if ($installResult.ResultCode -notin 2,3) {
    throw "Windows Update install failed: $($installResult.ResultCode)"
}
Write-Output 'FOG_UPDATE_STATE=INSTALLED'
Write-Output "Installed $($updates.Count) update(s)."
Write-Output "RebootRequired=$($installResult.RebootRequired)"
POWERSHELL
)

    for ((pass=1; pass<=WINDOWS_UPDATE_PASSES; pass++)); do
        log "Windows Update pass $pass/$WINDOWS_UPDATE_PASSES"
        if ! update_output=$(qm guest exec "$WINDOWS_VMID" \
            --timeout "$UPDATE_TIMEOUT" -- \
            powershell.exe -NoProfile -NonInteractive \
            -ExecutionPolicy Bypass -Command "$windows_update_ps" 2>&1); then
            printf '%s\n' "$update_output"
            die "Windows Update failed on pass $pass"
        fi
        printf '%s\n' "$update_output"

        if grep -q 'FOG_UPDATE_STATE=NO_UPDATES' <<<"$update_output"; then
            update_clean=1
            log "Windows Update reports no remaining software updates"
            break
        fi

        log "Rebooting Windows after update pass $pass"
        qm reboot "$WINDOWS_VMID"
        sleep 30
        wait_guest_agent "$WINDOWS_VMID" ||
            die "Windows did not return after update pass $pass"
        sleep 30
    done

    (( update_clean == 1 )) ||
        die "Windows still reports updates after $WINDOWS_UPDATE_PASSES passes; capture aborted"

    local bitlocker_output
    bitlocker_output=$(qm guest exec "$WINDOWS_VMID" --timeout 120 -- \
        powershell.exe -NoProfile -NonInteractive \
        -ExecutionPolicy Bypass -Command \
        '$volume = Get-BitLockerVolume -MountPoint "C:";
         Write-Output "VolumeStatus=$($volume.VolumeStatus)";
         Write-Output "EncryptionPercentage=$($volume.EncryptionPercentage)";
         if ($volume.VolumeStatus -eq "FullyDecrypted" -and
             $volume.EncryptionPercentage -eq 0) {
             Write-Output "FOG_BITLOCKER_OK"
         } else {
             Write-Error "BitLocker must be fully decrypted before capture"
             exit 41
         }' 2>&1 || true)
    printf '%s\n' "$bitlocker_output"
    grep -q 'FOG_BITLOCKER_OK' <<<"$bitlocker_output" ||
        die "Windows BitLocker is not fully decrypted; capture aborted"

    qm guest exec "$WINDOWS_VMID" --timeout 120 -- \
        cmd.exe /c "powercfg -h off"
    shutdown_vm "$WINDOWS_VMID"

    log "Windows updates completed and the VM restarted successfully"
    log "Validate BitLocker and the deployed image before approval"
}

restore_boot_orders() {
    qm set "$MINT_VMID" --boot order=scsi0 >/dev/null 2>&1 || true
    qm set "$UBUNTU_VMID" --boot order=scsi0 >/dev/null 2>&1 || true
    qm set "$WINDOWS_VMID" --boot order=sata0 >/dev/null 2>&1 || true
}

cleanup() {
    local rc=$?
    trap - EXIT INT TERM
    restore_boot_orders
    if (( rc != 0 )); then
        send_line "FOG automation FAILED on ${PROXMOX_IP}; check /var/log/pipeline.log"
    fi
    exit "$rc"
}

trap cleanup EXIT
trap 'exit 130' INT TERM

main() {
    log "Starting FOG master update and capture pipeline"

    install -d -m 0700 "$SLOT_STATE_DIR"

    ensure_vm_running "$FOG_VMID"
    wait_fog_ready || die "FOG Web/API did not become ready"

    ping -c 1 -W 2 "$NAS_IP" >/dev/null ||
        die "Synology NAS $NAS_IP is unreachable"

    if fog_has_any_active_task; then
        die "FOG already has an active task; do not cancel unrelated work"
    fi

    # Always boot the master operating systems from their disks for updates.
    restore_boot_orders

    update_linux "$MINT_VMID" "Linux Mint"
    capture_next_slot "$MINT_VMID" "$MINT_HOST_ID" "mint" "B" \
        "$MINT_IMAGE_A_ID" "$MINT_IMAGE_B_ID" \
        "LinuxMint-Master" "scsi0"

    update_linux "$UBUNTU_VMID" "Ubuntu"
    capture_next_slot "$UBUNTU_VMID" "$UBUNTU_HOST_ID" "ubuntu" "B" \
        "$UBUNTU_IMAGE_A_ID" "$UBUNTU_IMAGE_B_ID" \
        "Ubuntu-Master" "scsi0"

    update_windows
    capture_next_slot "$WINDOWS_VMID" "$WINDOWS_HOST_ID" "windows" "A" \
        "$WINDOWS_IMAGE_A_ID" "$WINDOWS_IMAGE_B_ID" \
        "Windows-Master" "sata0"

    send_line_flex_success

    log "Pipeline finished. Validate FOG Task History, Image Size, Captured date,"
    log "NAS files and a single-machine test deployment before approval"
}

main "$@"
