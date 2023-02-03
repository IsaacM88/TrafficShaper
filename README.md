# TrafficShaper
This is a bash script to shape network traffic on a computer by limiting upload and download bandwidth using tc. All settings changed by this script will reset to their defaults when the computer restarts. This script was tested on Fedora Workstation 37.

Install Traffic Control package.
```
sudo dnf install iproute-tc
```
Get your network interface name and update the user defined variables.
```
ip link show
vi /<PATH>/trafficshaper.sh
```
Have a look at the current state of “**tcp-segmentation-offload**”, “**generic-segmentation-offload**”, and “**generic-receive-offload**”. The script will toggle these on and off.
```
ethtool -k <INTERFACE>
```
Run the script with start/stop/status arguments.
```
sudo bash /path/trafficshaper.sh status
sudo bash /path/trafficshaper.sh stop
sudo bash /path/trafficshaper.sh start
```
Run LibreSpeed test: https://librespeed.org/
