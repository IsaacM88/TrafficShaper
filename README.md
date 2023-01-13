# TrafficShaper
This is a bash script to shape network traffic on a computer by limiting upload and download bandwidth with tc. All settings changed by this script will reset to default when the computer restarts. This script was made with Fedora Linux in mind.

Install Traffic Control package.
```
sudo dnf install iproute-tc
```
Have a look at the current state of “**tcp-segmentation-offload**”, “**generic-segmentation-offload**”, and “**generic-receive-offload**”. The script will toggle these on and off.
```
ethtool -k enp6s0
```
Get the network interface name and update the script variable as needed.
```
ip address
vi /path/trafficshaper.sh
```
Run the script with start/stop/status arguments.
```
sudo sh /path/trafficshaper.sh status
sudo sh /path/trafficshaper.sh stop
sudo sh /path/trafficshaper.sh start
```
Run LibreSpeed test: https://librespeed.org/
