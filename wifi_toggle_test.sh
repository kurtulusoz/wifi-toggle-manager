#!/bin/bash

# Configuration
INTERFACE="wlan0"
ETH_INTERFACE="eth0"
AP_IP="192.168.4.1"
CONF_FILE="/etc/hostapd/hostapd.conf"
WPA_SUPP_FILE="/etc/wpa_supplicant/wpa_supplicant_test.conf"
CLIENT_LOG="/var/log/ap_clients.log"

# Mode configuration (First parameter: ap or wifi)
MODE="${1:-ap}"
SSID="$2"
PASSWORD="$3"

# Root check
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo."
  exit 1
fi

# Print usage helper if mode is invalid
if [ "$MODE" != "ap" ] && [ "$MODE" != "wifi" ]; then
  echo "Usage: sudo $0 [ap|wifi] [ssid] [password]"
  echo "Example AP:   sudo $0 ap my_ap my_password123"
  echo "Example WIFI: sudo $0 wifi target_ap target_password"
  exit 1
fi

# --- CHECK IF CLIENT LOG FILE EXISTS BEFORE CREATING IT ---
if [ ! -f "$CLIENT_LOG" ]; then
  echo "[$(date)] Client log file not found. Creating $CLIENT_LOG..."
  touch "$CLIENT_LOG"
fi

# Helper function to stop everything and clean up network states
cleanup_all_services() {
    echo "[$(date)] Cleaning up and stopping network services..."
    systemctl stop hostapd 2>/dev/null || true
    systemctl stop dnsmasq 2>/dev/null || true
    killall wpa_supplicant 2>/dev/null || true
    iptables -F -t nat 2>/dev/null || true
    iptables -F 2>/dev/null || true
    ip addr del $AP_IP/24 dev $INTERFACE 2>/dev/null || true
    ip addr flush dev $INTERFACE 2>/dev/null || true
    ip link set "$INTERFACE" down
    sleep 1
}

# ==========================================
# MODE 1: ACCESS POINT (ap)
# ==========================================
if [ "$MODE" = "ap" ]; then
    # Fallback to defaults if not provided
    SSID="${SSID:-clarinox_pi}"
    PASSWORD="${PASSWORD:-clarinox}"

    # Validate password length for WPA2 AP
    if [ ${#PASSWORD} -lt 8 ]; then
      echo "Error: WPA2 AP password must be at least 8 characters long!"
      exit 1
    fi

    # Check eth0 status (carrier: 1 = connected)
    if [ -f /sys/class/net/$ETH_INTERFACE/carrier ] && [ "$(cat /sys/class/net/$ETH_INTERFACE/carrier 2>/dev/null)" = "1" ]; then
        
        if pgrep -x "hostapd" > /dev/null; then
            echo "[$(date)] AP is already active. Restarting services for new configuration..."
        fi
        
        cleanup_all_services

        echo "[$(date)] $ETH_INTERFACE active. Triggering AP sequence..."
        echo "[$(date)] Setting up AP with SSID: '$SSID'"

        # --- DYNAMICALLY GENERATE HOSTAPD CONFIGURATION ---
        cat << EOF > "$CONF_FILE"
interface=$INTERFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=7
wpa=2
wpa_key_mgmt=WPA-PSK
wpa_passphrase=$PASSWORD
rsn_pairwise=CCMP
EOF

        # --- INTERFACE INITIALIZATION ---
        rfkill unblock wifi
        sleep 0.5
        ip link set "$INTERFACE" up
        sleep 0.5
        ip addr add $AP_IP/24 dev $INTERFACE
        sleep 1

        # --- NAT & IP FORWARDING ---
        echo 1 > /proc/sys/net/ipv4/ip_forward
        iptables -t nat -A POSTROUTING -o $ETH_INTERFACE -j MASQUERADE
        iptables -A FORWARD -i $ETH_INTERFACE -o $INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
        iptables -A FORWARD -i $INTERFACE -o $ETH_INTERFACE -j ACCEPT

        # --- START AP SERVICES ---
        systemctl restart dnsmasq
        sleep 0.5
        systemctl restart hostapd
        
        if pgrep -x "hostapd" > /dev/null && pgrep -x "dnsmasq" > /dev/null; then
            echo "[$(date)] Access Point and DHCP Server successfully started."
            echo "[$(date)] AP STARTED: SSID='$SSID'" >> "$CLIENT_LOG"
        else
            echo "[$(date)] ERROR: Failed to start AP services properly."
            exit 1
        fi
    else
        echo "[$(date)] $ETH_INTERFACE inactive. Tearing down AP..."
        cleanup_all_services
        echo "[$(date)] AP STOPPED" >> "$CLIENT_LOG"
    fi

# ==========================================
# MODE 2: WI-FI CLIENT & TEST (wifi)
# ==========================================
elif [ "$MODE" = "wifi" ]; then
    if [ -z "$SSID" ] || [ -z "$PASSWORD" ]; then
        echo "Error: SSID and Password are required for wifi test mode!"
        echo "Usage: sudo $0 wifi [target_ssid] [target_password]"
        exit 1
    fi

    echo "[$(date)] Entering Wi-Fi Connection Test Mode..."
    cleanup_all_services

    # --- GENERATING BASE WPA_SUPPLICANT HEADER ---
    cat << EOF > "$WPA_SUPP_FILE"
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=TR
EOF

    # --- PRE-HASH COMPLEX PASSWORD AND APPEND SECURELY ---
    echo "[$(date)] Securely hashing profile credentials for SSID: '$SSID'..."
    wpa_passphrase "$SSID" "$PASSWORD" >> "$WPA_SUPP_FILE"

    # --- INITIALIZE INTERFACE AS CLIENT ---
    rfkill unblock wifi
    sleep 0.5
    ip link set "$INTERFACE" up
    sleep 0.5

    # --- CONNECT TO TARGET AP ---
    echo "[$(date)] Connecting to target network '$SSID'..."
    wpa_supplicant -B -i "$INTERFACE" -c "$WPA_SUPP_FILE" -D nl80211
    
    # Wait up to 15 seconds for connection authorization
    echo -n "[$(date)] Waiting for association..."
    for i in {1..15}; do
        if iw dev "$INTERFACE" link | grep -q "Connected to"; then
            echo " Associated successfully!"
            break
        fi
        echo -n "."
        sleep 1
    done

    # Check if successfully associated
    if ! iw dev "$INTERFACE" link | grep -q "Connected to"; then
        echo ""
        echo "[$(date)] ERROR: Failed to associate with '$SSID'. Check password or signal strength."
        rm -f "$WPA_SUPP_FILE"
        exit 1
    fi

    # --- REQUEST DHCP IP FROM TARGET AP ---
    echo "[$(date)] Requesting IP address via DHCP..."
    dhclient -v "$INTERFACE"

    # --- EXECUTE PING CONNECTION TEST ---
    echo "[$(date)] Testing network routing and internet connectivity..."
    sleep 2
    
    if ping -I "$INTERFACE" -c 3 8.8.8.8 > /dev/null 2>&1; then
        echo "[$(date)] SUCCESS: Internet connectivity test passed over Wi-Fi!"
        iw dev "$INTERFACE" link
    else
        echo "[$(date)] WARNING: Associated with Wi-Fi, but Internet/Ping test FAILED."
    fi

    # Clean up temporary configuration file
    rm -f "$WPA_SUPP_FILE"
fi