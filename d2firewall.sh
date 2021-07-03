#!/bin/bash
#credits to @BasRaayman and @inchenzo

ALGO="bm"
INTERFACE=$(cat interface.txt 2>/dev/null || echo "tun0")
NETWORK=$(cat network.txt 2>/dev/null || echo "10.8.0.0/24")
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

while getopts "a:" opt; do
  case $opt in
    a) action=$OPTARG ;;
    *) echo 'Not a valid command' >&2
       exit 1
  esac
done

reset_ip_tables () {

  # start iptables service if not started
  if service iptables status | grep -q dead; then
    service iptables start
  fi

  # reset iptables to default
  iptables -P INPUT ACCEPT
  iptables -P FORWARD ACCEPT
  iptables -P OUTPUT ACCEPT

  iptables -F
  iptables -X

  # allow openvpn
  if ( ip a | grep -q "tun0" ) && [ "$INTERFACE" == "tun0" ]; then
    if ! iptables-save | grep -q "POSTROUTING -s 10.8.0.0/24"; then
      iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
    fi
    iptables -A INPUT -p udp -m udp --dport 1194 -j ACCEPT
    iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -s 10.8.0.0/24 -j ACCEPT
  fi
}

get_platform_match_str () {
  local val="psn-4"
  if [ "$1" == "psn" ]; then
    val="psn-4"
  elif [ "$1" == "xbox" ]; then
    val="xboxpwid:"
  elif [ "$1" == "steam" ]; then
    val="steamid:"
  fi
  echo $val
}

auto_sniffer () {
  echo -e "${RED}Press any key to stop sniffing. DO NOT CTRL C${NC}"
  sleep 1

  #sniff the ids based on platform
  if [ "$1" == "psn" ]; then
    ngrep -l -q -W byline -d "$INTERFACE" "psn-4" udp | grep --line-buffered -o -P 'psn-4[0]{8}\K[A-F0-9]{7}' | tee -a "$2" &
  elif [ "$1" == "xbox" ]; then
    ngrep -l -q -W byline -d "$INTERFACE" "xboxpwid:" udp | grep --line-buffered -o -P 'xboxpwid:\K[A-F0-9]{32}' | tee -a "$2" &
  elif [ "$1" == "steam" ]; then
    ngrep -l -q -W byline -d "$INTERFACE" "steamid:" udp | grep --line-buffered -o -P 'steamid:\K[0-9]{17}' | tee -a "$2" &
  fi

  #run infinitely until key is pressed
  while [ true ] ; do
    read -t 1 -n 1
    if [ $? = 0 ] ; then
      break
    fi
  done
  pkill -15 ngrep
}

install_dependencies () {

  # enable ip forwarding
  sysctl -w net.ipv4.ip_forward=1 > /dev/null

  # disable ufw firewall
  ufw disable > /dev/null
  service ufw stop > /dev/null
  systemctl disable ufw > /dev/null

  # check if openvpn is already installed
  if ip a | grep -q "tun0"; then
    yn="n"
  else 
    echo -e -n "${GREEN}Would you like to install OpenVPN?${NC} y/n: "
    read yn
    yn=${yn:-"y"}
  fi
  
  if [[ $yn =~ ^(y|yes)$ ]]; then
    
   echo -e -n "${GREEN}Is this for a local/home setup? ${RED}(Answer no if AWS/VPS)${NC} y/n: "
    read ans
    ans=${ans:-"y"}

    if [[ $ans =~ ^(y|yes)$ ]]; then
      # Put all IPs except for IPv6, loopback and openVPN in an array
      ip_address_list=( $( ip a | grep inet | grep -v -e 10.8. -e 127.0.0.1 -e inet6 | awk '{ print $2 }' | cut -f1 -d"/" ) )
      
      echo "Please enter the number which corresponds to the private IP address of your device that connects to your local network: "
      i=1
      # Show all addresses in a numbered list
      for address in "${ip_address_list[@]}"; do
        echo "    $i) $address"
        ((i++))
      done
      
      # Have them type out which IP connects to the internet and set IP address based off of that
      read -p "Choice: " ip_line_number
      ip_list_index=$((ip_line_number - 1))
      ip="${ip_address_list[$ip_list_index]}"
      if [ -z $ip ]; then
        echo "Ip does not exist."
        exit 1;
      fi
    else
      # get public ipv4 address
      ip=$(dig +short myip.opendns.com @resolver1.opendns.com)
    fi;

    echo -e "${RED}Installing dependencies. Please wait while it finishes...${NC}"
    apt-get update > /dev/null
  
    # install dependencies
    DEBIAN_FRONTEND=noninteractive apt-get -y -q install iptables iptables-persistent ngrep nginx > /dev/null
    systemctl enable iptables

    # start nginx web service
    service nginx start
    
    # check if curl is already installed
    if command -V curl > /dev/null 2>&1; then
      #curl is available
    else
      #curl is not available
      DEBIAN_FRONTEND=noninteractive apt-get -y -q install curl > /dev/null
    fi

    echo -e "${RED}Installing OpenVPN. Please wait while it finishes...${NC}"
    curl -s -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh > /dev/null
    chmod +x ./openvpn-install.sh
    (ENDPOINT="$ip" APPROVE_INSTALL=y APPROVE_IP=y IPV6_SUPPORT=n PORT_CHOICE=1 PROTOCOL_CHOICE=1 DNS=1 COMPRESSION_ENABLED=n CUSTOMIZE_ENC=n CLIENT=client PASS=1 ./openvpn-install.sh) &
    wait;

    # move openvpn config to public web folder
    cp /"$SUDO_USER"/client.ovpn /var/www/html/client.ovpn
    
    clear
    echo -e "${GREEN}You can download the openvpn config from ${BLUE}http://$ip/client.ovpn"
    echo -e "${GREEN}If you are unable to access this file, you may need to allow/open the http port 80 with your vps provider."
    echo -e "Otherwise you can always run the command cat /root/client.ovpn and copy/paste ALL of its contents in a file on your PC."
    echo -e "It will be deleted automatically in 15 minutes for security reasons."
    echo -e "Be sure to import this config to your router and connect your consoles before proceeding any further.${NC}"

    # stop nginx web service after 15 minutes and delete openvpn config
    nohup bash -c 'sleep 900 && service nginx stop && apt remove nginx -y && rm /var/www/html/client.ovpn' &>/dev/null &
  else
    DEBIAN_FRONTEND=noninteractive apt-get -y -q install iptables iptables-persistent ngrep > /dev/null
  fi
  
}

setup () {

  if [ -z "$1" ]; then
    echo -e "${GREEN}Setting up firewall rules.${NC}"
  fi
  
  reset_ip_tables

  read -p "Enter your platform xbox, psn, steam: " platform
  platform=$(echo "$platform" | xargs)
  platform=${platform:-"psn"}

  reject_str=$(get_platform_match_str "$platform")
  echo "$platform" > /tmp/data.txt

  read -p "Enter your network/netmask: " net
  net=$(echo "$net" | xargs)
  net=${net:-$NETWORK}
  echo "$net" >> /tmp/data.txt

  ids=()
  read -p "Would you like to sniff the ID automatically?(psn/xbox/steam) y/n: " yn
  yn=${yn:-"y"}
  if ! [[ $platform =~ ^(psn|xbox|steam)$ ]]; then
    yn="n"
  fi
  echo "n" >> /tmp/data.txt

  #auto sniffer
  if [[ $yn =~ ^(y|yes)$ ]]; then
    echo -e "${RED}Please have the fireteam leaders join each other in orbit.${NC}"

    auto_sniffer "$platform" "/tmp/data.txt"

    #remove duplicates
    awk '!a[$0]++' /tmp/data.txt > /tmp/temp.txt && mv /tmp/temp.txt /tmp/data.txt

    #get number of accounts
    snum=$(tail -n +4 /tmp/data.txt | wc -l)
    awk "NR==4{print $snum}1" /tmp/data.txt > /tmp/temp.txt && mv /tmp/temp.txt /tmp/data.txt

    #get ids and add to ads array with identifier
    tmp_ids=$(tail -n +5 /tmp/data.txt)
    c=1
    while IFS= read -r line; do 
      idf="system$c"
      ids+=( "$idf;$line" )
      ((c++))
    done <<< "$tmp_ids"
  else 
    #add ids manually

    if [ -z "$1" ]; then
      echo -e "${RED}Please add the 2 fireteam leaders first.${NC}"
    fi

    read -p "How many account IDs do you want to add? " snum
    if [ "$snum" -lt 1 ]; then
      exit 1;
    fi;
    echo "$snum" >> /tmp/data.txt
    for ((i = 0; i < snum; i++))
    do 
      num=$(( $i + 1 ))
      if [ $num -lt 3 ]; then
        who="Fireteam Leader"
      else
        who="Player"
      fi
      idf="system$num"
      read -p "Enter the sniffed Account ID for $who $num: " sid
      sid=$(echo "$sid" | xargs)
      echo "$sid" >> /tmp/data.txt
      ids+=( "$idf;$sid" )
    done
  fi;
  mv /tmp/data.txt data.txt
  chown "$SUDO_USER":"$SUDO_USER" data.txt

  iptables -I FORWARD -i "$INTERFACE" -p udp --dport 27000:27200 -m string --string "$reject_str" --algo "$ALGO" -j REJECT
  
  n=${#ids[*]}
  INDEX=1
  for (( i = n-1; i >= 0; i-- ))
  do
    elem=${ids[i]}
    IFS=';' read -r -a id <<< "$elem"
    offset=$((n - 2))
    if [ $INDEX -gt $offset ]; then
      iptables -N "${id[0]}"
      iptables -I FORWARD -i "$INTERFACE" -s "$net" -p udp --dport 27000:27200 -m string --string "${id[1]}" --algo "$ALGO" -j "${id[0]}"
    else
      iptables -I FORWARD -i "$INTERFACE" -s "$net" -p udp --dport 27000:27200 -m string --string "${id[1]}" --algo "$ALGO" -j ACCEPT
    fi
    ((INDEX++))
  done
  
  INDEX1=1
  for i in "${ids[@]}"
  do
    if [ $INDEX1 -gt 2 ]; then
      break
    fi
    IFS=';' read -r -a id <<< "$i"
    INDEX2=1
    for j in "${ids[@]}"
    do
      if [ $INDEX2 -gt 2 ]; then
        break
      fi
      if [ "$i" != "$j" ]; then
        IFS=';' read -r -a idx <<< "$j"
        iptables -A "${id[0]}" -i "$INTERFACE" -s "$net" -p udp --dport 27000:27200 -m string --string "${idx[1]}" --algo "$ALGO" -j ACCEPT
      fi
      ((INDEX2++))
    done
    ((INDEX1++))
  done

  if [ -z "$1" ]; then
    echo -e "${GREEN}Setup is complete and Matchmaking Firewall is now active.${NC}"
  fi
}

add () {
  echo -e -n "${GREEN}Enter the sniffed ID: ${NC}"
  read id
  id=$(echo "$id" | xargs)
  if [ -n "$id" ]; then
    echo "$id" >> data.txt
    n=$(sed -n '4p' < data.txt)
    ((n++))
    sed -i "4c$n" data.txt
    read -p "Would you like to enter another ID? y/n " yn
    yn=${yn:-"y"}
    if [[ $yn =~ ^(y|yes)$ ]]; then
      add
    else
      setup true < data.txt
    fi
  fi
}

open () {
  if iptables-save | grep -q "REJECT"; then
    echo -e "${RED}Matchmaking is no longer being restricted.${NC}"
    platform=$(sed -n '1p' < data.txt)
    reject_str=$(get_platform_match_str "$platform")
    iptables -D FORWARD -i "$INTERFACE" -p udp --dport 27000:27200 -m string --string "$reject_str" --algo "$ALGO" -j REJECT
  fi
}

close () {
  if ! iptables-save | grep -q "REJECT"; then
    echo -e "${RED}Matchmaking is now being restricted.${NC}"
    platform=$(sed -n '1p' < data.txt)
    reject_str=$(get_platform_match_str "$platform")
    pos=$(iptables -L FORWARD | grep -c "system")
    ((pos++))
    iptables -I FORWARD "$pos" -i "$INTERFACE" -p udp --dport 27000:27200 -m string --string "$reject_str" --algo "$ALGO" -j REJECT
  fi
}

if [ "$action" == "setup" ]; then
  if ! command -v ngrep &> /dev/null
  then
      install_dependencies
  fi
  setup
elif [ "$action" == "stop" ]; then
  echo "This command is depreciated. Please run: sudo bash d2firewall.sh -a open"
  open
elif [ "$action" == "start" ]; then
  echo "This command is depreciated. Please run: sudo bash d2firewall.sh -a close"
  close
elif [ "$action" == "open" ]; then
  open
elif [ "$action" == "close" ]; then
  close
elif [ "$action" == "add" ]; then
  add
elif [ "$action" == "remove" ]; then
  # display list of ids to user
  list=$(tail -n +5 data.txt | cat -n)
  echo "$list"
  total=$(echo "$list" | wc -l)
  echo -e -n "${GREEN}How many IDs do you want to remove from the end of this list? ${NC}"
  read num
  if [[ $num -gt 0 && $num -le $total ]]; then
    head -n -"$num" data.txt > /tmp/data.txt && mv /tmp/data.txt ./data.txt
    n=$(sed -n '4p' < data.txt)
    n=$((n-num))
    sed -i "4c$n" data.txt
    setup true < data.txt
  fi;
elif [ "$action" == "sniff" ]; then
  platform=$(sed -n '1p' < data.txt)
  if ! [[ $platform =~ ^(psn|xbox|steam)$ ]]; then
      echo "Only psn,xbox, and steam are supported atm."
    exit 1
  fi
  # allow players to join fireteam
  open

  # automatically sniff the joining players account id
  echo -e "${RED}Please have the players join on the fireteam leaders in orbit.${NC}"
  auto_sniffer "$platform" "data.txt"

  # remove duplicates
  awk '!a[$0]++' data.txt > /tmp/data.txt && mv /tmp/data.txt data.txt
  chown "$SUDO_USER":"$SUDO_USER" data.txt 

  # update total number of ids
  n=$(tail -n +5 data.txt | wc -l)
  sed -i "4c$n" data.txt

  setup true < data.txt

elif [ "$action" == "list" ]; then
  # list the ids added to the data.txt file
  tail -n +5 data.txt | cat -n
elif [ "$action" == "update" ]; then
  wget -q https://raw.githubusercontent.com/fswdevl/Destiny-2-SDR-Matchmaking-Firewall/main/d2firewall.sh -O ./d2firewall.sh
  chmod +x ./d2firewall.sh
  echo -e "${GREEN}Script update complete."
  echo -e "Please rerun the initial setup to avoid any issues.${NC}"
elif [ "$action" == "load" ]; then
  echo -e "${GREEN}Loading firewall rules.${NC}"
  if [ -f data.txt ]; then
      setup true < data.txt
  fi
elif [ "$action" == "reset" ]; then
  echo -e "${RED}Erasing all firewall rules.${NC}"
  reset_ip_tables
fi
