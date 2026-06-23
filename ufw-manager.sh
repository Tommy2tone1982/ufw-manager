#!/bin/bash

# Trigger sudo elevation right at the start if not already root
if [ "$EUID" -ne 0 ]; then
    echo "🔒 This script requires administrator privileges."
    echo "Please enter your password to authenticate:"
    exec sudo "$0" "$@"
fi

# Locate the UFW binary dynamically to prevent "command not found" errors
UFW_BIN=$(which ufw || echo "/usr/sbin/ufw")

# Verify UFW is actually installed
if [ ! -f "$UFW_BIN" ]; then
    echo "❌ Error: UFW is not installed on this system."
    echo "Please install it using your package manager (e.g., sudo apt install ufw)"
    exit 1
fi

# Function to check if IPv6 is enabled in UFW config
get_ipv6_status() {
    if grep -q '^IPV6=yes' /etc/default/ufw; then
        echo "Enabled"
    else
        echo "Disabled"
    fi
}

# Function to display the menu
show_menu() {
    local ipv6_status=$(get_ipv6_status)
    echo ""
    echo "================================="
    echo "    🔥 Interactive UFW Manager   "
    echo "================================="
    echo "1) Check UFW Status & Current Rules"
    echo "2) Allow Ports (Continuous Mode)"
    echo "3) Allow Ports for Specific IP/Subnet (Continuous Mode)"
    echo "4) Deny/Block an IP Address"
    echo "5) Delete Rules (Continuous Mode)"
    echo "6) Enable UFW"
    echo "7) Disable UFW"
    echo "8) Toggle IPv6 Rule Creation [Current: $ipv6_status]"
    echo "9) Exit"
    echo "================================="
}

# Main loop
while true; do
    show_menu
    read -p "Choose an option [1-9]: " choice
    echo ""

    # Track success of the chosen action (0 = success, 1 = failure/pause required)
    status_code=0

    case $choice in
        1)
            echo "📋 Current UFW Status:"
            $UFW_BIN status numbered
            status_code=1
            ;;
        
        2)
            # Continuous Port Addition Loop
            while true; do
                read -p "Enter the port number to ALLOW (or 'r' to return to main menu): " port
                
                if [[ "$port" =~ ^[Rr]$ ]]; then
                    echo "↩️ Returning to main menu..."
                    break
                fi

                if [ -z "$port" ]; then
                    echo "❌ Port cannot be blank."
                    echo ""
                    continue
                fi

                read -p "Protocol? [t]cp / [u]dp / [Enter] for any: " proto_input
                # Convert to lowercase to handle inputs safely
                proto_input=$(echo "$proto_input" | tr '[:upper:]' '[:lower:]')

                if [ "$proto_input" = "t" ]; then
                    proto="tcp"
                elif [ "$proto_input" = "u" ]; then
                    proto="udp"
                else
                    proto="any"
                fi

                echo "⏳ Applying rule..."
                if [ "$proto" = "any" ]; then
                    error_msg=$($UFW_BIN allow "$port" 2>&1)
                else
                    error_msg=$($UFW_BIN allow "$port/$proto" 2>&1)
                fi

                if [ $? -eq 0 ]; then
                    echo "✅ Rule for port $port ($proto) added successfully."
                    echo "---------------------------------"
                else
                    echo "❌ UFW Error: $error_msg"
                    echo ""
                    read -p "Press [Enter] to try again..." dummy
                fi
                echo ""
            done
            status_code=0
            ;;

        3)
            read -p "Enter the IP address or Subnet (e.g., 192.168.1.50 or 10.0.0.0/24): " ip
            
            if [ -z "$ip" ]; then
                echo "❌ IP or Subnet cannot be blank."
                status_code=1
                continue
            fi

            echo "🌐 Target set to: $ip"
            echo "---------------------------------"

            # Continuous Nested Loop for adding multiple ports to THIS specific subnet/IP
            while true; do
                read -p "Enter a port to allow for $ip (leave blank for ALL ports, or 'r' for main menu): " port
                
                if [[ "$port" =~ ^[Rr]$ ]]; then
                    echo "↩️ Returning to main menu..."
                    break
                fi

                read -p "Protocol? [t]cp / [u]dp / [Enter] for any: " proto_input
                proto_input=$(echo "$proto_input" | tr '[:upper:]' '[:lower:]')

                if [ "$proto_input" = "t" ]; then
                    proto="tcp"
                elif [ "$proto_input" = "u" ]; then
                    proto="udp"
                else
                    proto="any"
                fi

                echo "⏳ Applying rule..."
                if [ -z "$port" ]; then
                    error_msg=$($UFW_BIN allow from "$ip" 2>&1)
                    port_display="ALL"
                else
                    if [ "$proto" = "any" ]; then
                        error_msg=$($UFW_BIN allow from "$ip" to any port "$port" 2>&1)
                    else
                        error_msg=$($UFW_BIN allow from "$ip" to any port "$port" proto "$proto" 2>&1)
                    fi
                    port_display="$port"
                fi

                if [ $? -eq 0 ]; then
                    echo "✅ Allowed access from $ip to port $port_display ($proto)."
                    echo "---------------------------------"
                else
                    echo "❌ UFW Error: $error_msg"
                    echo ""
                    read -p "Press [Enter] to try again..." dummy
                fi

                if [ -z "$port" ]; then
                    echo "ℹ️ All ports allowed for $ip. Exiting subnet loop."
                    break
                fi
                echo ""
            done
            status_code=0
            ;;

        4)
            read -p "Enter the IP address or Subnet to BLOCK: " ip
            echo "⏳ Applying block..."
            error_msg=$($UFW_BIN deny from "$ip" 2>&1)
            
            if [ $? -eq 0 ]; then
                echo "🚫 IP successfully blocked."
                status_code=0
            else
                echo "❌ UFW Error: $error_msg"
                status_code=1
            fi
            ;;

        5)
            # Continuous Deletion Loop
            while true; do
                echo "📋 Current numbered rules:"
                $UFW_BIN status numbered
                echo ""
                read -p "Enter the rule number to DELETE (or 'r' to return to main menu): " rule_num
                
                if [[ "$rule_num" =~ ^[Rr]$ ]]; then
                    echo "↩️ Returning to main menu..."
                    break
                fi

                if [[ "$rule_num" =~ ^[0-9]+$ ]]; then
                    error_msg=$($UFW_BIN --force delete "$rule_num" 2>&1)
                    if [ $? -eq 0 ]; then
                        echo "🗑️ Rule #$rule_num deleted successfully."
                        echo "---------------------------------"
                    else
                        echo "❌ UFW Error: $error_msg"
                        echo ""
                        read -p "Press [Enter] to try again..." dummy
                    fi
                else
                    echo "❌ Invalid input. Please enter a valid rule number or 'r'."
                    echo ""
                    read -p "Press [Enter] to try again..." dummy
                fi
                echo ""
            done
            status_code=0
            ;;

        6)
            echo "🚀 Enabling UFW..."
            $UFW_BIN enable
            status_code=0
            ;;

        7)
            echo "🛑 Disabling UFW..."
            $UFW_BIN disable
            status_code=0
            ;;

        8)
            current_ipv6=$(get_ipv6_status)
            if [ "$current_ipv6" = "Enabled" ]; then
                echo "⚙️ Disabling IPv6 in UFW configuration..."
                sed -i 's/^IPV6=yes/IPV6=no/' /etc/default/ufw
                echo "🚫 IPv6 rule creation turned OFF."
            else
                echo "⚙️ Enabling IPv6 in UFW configuration..."
                sed -i 's/^IPV6=no/IPV6=yes/' /etc/default/ufw
                echo "🌐 IPv6 rule creation turned ON."
            fi
            
            if $UFW_BIN status | grep -q "Status: active"; then
                echo "🔄 Reloading UFW to apply changes..."
                $UFW_BIN reload
            fi
            status_code=0
            ;;

        9)
            echo "👋 Exiting. Stay secure!"
            exit 0
            ;;

        *)
            echo "❌ Invalid option, please try again."
            status_code=1
            ;;
    esac

    # Global menu pause rule
    if [ "$status_code" -ne 0 ]; then
        echo ""
        read -p "Press [Enter] to return to the menu..." dummy
    fi
done
