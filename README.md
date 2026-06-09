# Wi-Fi Toggle Test Script

A bash script for managing Wi-Fi operations on Linux-based embedded devices (e.g., Raspberry Pi). It supports two modes: **Access Point (AP)** and **Wi-Fi Client**, allowing you to quickly switch between hosting a network and connecting to one.

## Requirements

Before using this script, ensure the following packages are installed on your system:

| Package            | Purpose                          |
|--------------------|----------------------------------|
| `hostapd`          | Access Point daemon              |
| `dnsmasq`          | DHCP and DNS server              |
| `wpa_supplicant`   | Wi-Fi client authentication      |
| `iw`               | Wireless device configuration    |
| `rfkill`           | Radio (Wi-Fi/Bluetooth) control  |
| `iptables`         | NAT and firewall rules           |
| `dhclient`         | DHCP client for obtaining IP     |

You can install them on Debian-based systems with:

```bash
sudo apt update
sudo apt install hostapd dnsmasq wpasupplicant iw rfkill iptables isc-dhcp-client
```

## Usage

The script must be run with **root privileges** (sudo). It accepts up to three arguments:

```bash
sudo ./wifi_toggle_test.sh [mode] [ssid] [password]
```

### Arguments

| Argument   | Description                                          | Required    |
|------------|------------------------------------------------------|-------------|
| `mode`     | Operation mode: `ap` or `wifi`                       | Yes         |
| `ssid`     | Network name (SSID)                                  | Depends on mode |
| `password` | Network password (WPA2 passphrase)                   | Depends on mode |

### Examples

**Start Access Point mode** (uses default SSID and password if not provided):

```bash
# With custom credentials (password must be at least 8 characters)
sudo ./wifi_toggle_test.sh ap my_hotspot securepass123

# With default credentials (SSID: raspberry_pi, Password: raspberry)
sudo ./wifi_toggle_test.sh ap
```

**Connect to an existing Wi-Fi network and test connectivity:**

```bash
sudo ./wifi_toggle_test.sh wifi home_network mywifipassword
```

## How It Works

### AP Mode (Access Point)

In this mode, the device turns itself into a wireless access point. Other devices can connect to it and access the internet through the device's Ethernet interface (`eth0`).

The script performs the following steps:

1. **Validates** the Wi-Fi password (minimum 8 characters).
2. **Checks** whether the Ethernet interface (`eth0`) has an active connection.
3. **Stops** any previously running network services to avoid conflicts.
4. **Generates** a fresh `hostapd` configuration file with the provided SSID and password.
5. **Enables** the wireless interface and assigns it a static IP address (`192.168.4.1`).
6. **Configures** NAT (Network Address Translation) and IP forwarding so connected clients can reach the internet through `eth0`.
7. **Starts** `dnsmasq` (DHCP server) and `hostapd` (access point daemon).
8. **Logs** the event to `/var/log/ap_clients.log`.

If the Ethernet cable is disconnected, the script automatically tears down the access point and logs the shutdown.

### Wi-Fi Client Mode

In this mode, the device connects to an existing Wi-Fi network as a client and runs a connectivity test.

The script performs the following steps:

1. **Requires** both SSID and password arguments.
2. **Cleans up** any active network services.
3. **Generates** a temporary `wpa_supplicant` configuration file with the target network credentials.
4. **Hashes** the password securely using `wpa_passphrase` before storing it.
5. **Brings up** the wireless interface and attempts to associate with the target network (waits up to 15 seconds).
6. **Requests** an IP address via DHCP.
7. **Runs a ping test** to `8.8.8.8` (Google DNS) to verify internet connectivity.
8. **Removes** the temporary configuration file after the test.

## Configuration Variables

You can modify the following variables at the top of the script to match your setup:

| Variable           | Default Value                            | Description                      |
|--------------------|------------------------------------------|----------------------------------|
| `INTERFACE`        | `wlan0`                                  | Wireless interface name          |
| `ETH_INTERFACE`    | `eth0`                                   | Ethernet interface name          |
| `AP_IP`            | `192.168.4.1`                            | Static IP for the access point   |
| `CONF_FILE`        | `/etc/hostapd/hostapd.conf`              | hostapd configuration file path  |
| `WPA_SUPP_FILE`    | `/etc/wpa_supplicant/wpa_supplicant_test.conf` | Temp wpa_supplicant config  |
| `CLIENT_LOG`       | `/var/log/ap_clients.log`                | Log file for AP events           |

## Logging

All access point startup and shutdown events are recorded in `/var/log/ap_clients.log` with timestamps. The client log file is created automatically if it does not exist.

Example log entries:

```
[Mon Jun  9 10:30:00 +03 2026] AP STARTED: SSID='my_hotspot'
[Mon Jun  9 10:45:00 +03 2026] AP STOPPED
```

## Common Issues

| Problem                                     | Likely Cause / Solution                                                   |
|---------------------------------------------|---------------------------------------------------------------------------|
| "Please run this script with sudo"          | The script needs root privileges. Run it with `sudo`.                     |
| "Failed to associate with SSID"             | Double-check the password. Make sure the target AP is within range.       |
| "WPA2 AP password must be at least 8 characters" | Provide a longer password (minimum 8 characters required by WPA2).    |
| AP services fail to start                   | Verify that `hostapd` and `dnsmasq` are installed and not already running.|
| No internet access for AP clients           | Ensure the Ethernet interface (`eth0`) has an active internet connection. |

## Notes

- This script has been tested with the **Maya W-276** Wi-Fi adapter.
- The script **flushes** all existing IP addresses on the wireless interface and resets `iptables` rules during cleanup. Make sure no critical firewall rules depend on the default chain state.
- The temporary `wpa_supplicant` configuration file is deleted after the Wi-Fi client test completes — the plaintext password is not left on disk.
- This script is designed for **systemd-based** Linux distributions (e.g., Raspberry Pi OS, Ubuntu, Debian).

## License

This project is provided as-is for testing and development purposes.