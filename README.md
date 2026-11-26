# My Homelab
I use my homelab to self host services, run my personal projects and practice networking.

## Self Hosting

<img width="800" height="600" alt="20261126_205803" src="https://github.com/user-attachments/assets/18ef2050-2b8d-48de-b07a-98a94dba5c95" />

I self host multiple services on a single Proxmox Node which I built out of spare PC parts I had laying around. The node is made up of Debian VMs and CTs, these services include a NAS for data storage, Immich which runs on top of the NAS for easier photo management, BitWarden which I use as my Password Manager, Tailscale which I use to remotely connect to my homelab network and my [Plane Tracker](https://github.com/PrzemekWasinski/PlaneTracker).

The Proxmox Node has the OS, VMs and CTs all stored on a 512GB NVME SSD while all the data is stored on external drives, the drives used are 2x 2TB 3.5" HDDs, these are very loud so they are almost always off except when data is being backed up to them. All of my data is stored and is always accessible on 2x 2.5" SSDs, one is 1TB (For photos, videos files etc) and the other is 128GB (For storing my projects) these are quiet and run 24/7, everyday at 7am all the data from the SSDs is synced onto the HDDs providing me with 2 backups.

Because I decided to save money and not get a case I had the problem of turning the node on and off, at first I used a screwdriver to bridge the 2 power pins on the motherboard but then I realised I could use parts from my Arduino kit to create a power button, restart button, power LED and disk read/write LED.

Hardware list:
- CPU: Ryzen 5 2600
- GPU: GTX 1050ti
- Motherboard: Asus TUF B450
- RAM: 16GB 2666MHz
- SSD: 512GB NVMe
- Storage: 2x 2TB 3.5" HDDs, 1x 1TB 2.5" SSD, 1x 128GB 2.5" SSD
- Case: None

##  Networking

<img width="800" height="600" alt="20261126_205616" src="https://github.com/user-attachments/assets/98e04f55-ac7e-4fed-af16-5ca0ec43ab66" />

I deployed OPNSense on an old Dell Optiplex 3050 which seperates my homelab from my home ISP network, allowing me to experiment without taking my whole house offline. I use a HP ProCurve 1810G 24 Port Managed Switch which I got for free from my job and I use a TP-Link Deco S7 as my wireless access point so I can connect to devices such as my [Satellite Ground Station](https://github.com/PrzemekWasinski/SatelliteGroundStation) which is in my garden. The monitor is being used to display Grafana which monitors all of my servers.

I am soon planning to deploy DNS server to reach servers by name and seperate different servers and devices on different VLANs.

## Projects

<img width="800" height="600" alt="20261126_205625" src="https://github.com/user-attachments/assets/439a626a-c6eb-44a2-b9bf-8d11a41a8c1a" />

A few of my projects are to do with radio and require an antenna outside which is why I mounted these Raspberry Pis by my loft window, the one on the right feeds aircraft radio signals to Flight Radar 24 to improve coverage in my area while the one on the left used to host my own [Plane Tracker](https://github.com/PrzemekWasinski/PlaneTracker), due to hardware requirements this was moved to the Proxmox node and the Pi now runs Prometheus and Grafana for server monitoring.
