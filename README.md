# Destiny 2 SDR Matchmaking Firewall

## Download
#### Clone repo or run this command:
```wget -q https://raw.githubusercontent.com/CustosSolis/Destiny-2-SDR-Matchmaking-Firewall/main/d2firewall.sh -O ./d2firewall.sh```
## Usage
#### Setup: initial setup
``` sudo bash d2firewall.sh -a setup ```
#### Add: add a sniffed id to your firewall
``` sudo bash d2firewall.sh -a add ```
#### Remove: remove ids from the end of the list
``` sudo bash d2firewall.sh -a remove ```
#### Sniff: Auto sniffer. (You must add your 2 host consoles prior to running this)
``` sudo bash d2firewall.sh -a sniff ```
#### Open: Enables public matchmaking
``` sudo bash d2firewall.sh -a open ```
#### Close: Disables public matchmaking
``` sudo bash d2firewall.sh -a close ```
#### List: List the current accounts
``` sudo bash d2firewall.sh -a list ```
#### Update: Update the script to the newest version.
``` sudo bash d2firewall.sh -a update ```
#### Load: Load the saved rules after a reboot
``` sudo bash d2firewall.sh -a load ```
#### Reset: Reset iptables to default
``` sudo bash d2firewall.sh -a reset ```

### Details:
#### This script is written to work in a Ubuntu System. It uses the linux iptables firewall and openvpn.
#### It is tested to work on PSN, Xbox and Steam.
#### The first two accounts added must be the hosts of each fireteam.
#### If the firewall is active, accounts that are not already in the firewall will be unable to join the fireteam. You can run the auto sniffer to add them.
#### Please do not run this on your personal computer it will clobber your firewall rules. It is meant to be run in an isolated enviroment (vm, vps, spare pc).
#### Credits to inchenzo & BasRaayman for coming up with the method.
