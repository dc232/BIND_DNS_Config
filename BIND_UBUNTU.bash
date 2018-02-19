#!/bin/bash
#################################################
#Global Varibales
#################################################
INTERFACES="/etc/network/interfaces"
BIND9_SYSLOG="/var/log/syslog"
IPADDR=$(hostname -I)
VAR_LOG_MESSAGES="/var/log/messages"
DNS_LOCAL_OPTIONS="/etc/bind/named.conf.options"
#################################################

#when you set up the machine make sure to call it vjlocal inorder for the script to work

BIND () {
sudo apt install bind9 -y
}


#below is the new way of coding functions
networking_status_check () {
STAT_NET=$(sudo systemctl status networking | grep active)
STAT_NET_FAULT=$(sudo systemctl status networking | grep failed)
if [ "$STAT_NET" ]; then
echo $STAT_NET
else
cat << EOF
#################################################
A fault has been found with the networking configuration 
reverting back to the original configuration
#################################################
EOF
sleep 2
echo $STAT_NET_FAULT
echo $(systemctl status networking.service)
cat  $INTERFACES
sleep 10
echo starting diagnostics
mv $INTERFACES.back $INTERFACES
sudo service networking start
fi
}

networking () {
sudo cp $INTERFACES $INTERFACES.back
echo 'appending config to' $INTERFACES
sudo sed -i 's/dhcp/static/' $INTERFACES #see https://www.cyberciti.biz/faq/how-to-use-sed-to-find-and-replace-text-in-files-in-linux-unix-shell/ for more info 
#essentially the s means subsititue so in this case substitute dhcp for static
sudo sed -i "12 a address 10.0.0.253" $INTERFACES #a in this case means append after line 12, 13i means insert at line 13, this dosn't work becuase there is nothing in line 13
sudo sed -i "13 a netmask 255.0.0.0" $INTERFACES
sudo sed -i "14 a gateway 10.0.0.1" $INTERFACES
sudo sed -i "15 a dns-nameservers 127.0.0.1" $INTERFACES #10.0.0.254 well use this one as a forwarder later
sudo sed -i "16 a iface enp0s3 inet6 auto" $INTERFACES
echo 'change config from DHCP to static'
sleep 5
sudo service networking restart
networking_status_check
}

ssl() {
cat << EOF
#################################################
Creating SSH KEYS
#################################################
EOF
sleep 2

ssh localhost true #true is used to exit the sub shell otherwise the script wont  run utill you exit
cd ~/.ssh
ssh-keygen -f ~/.ssh/id_rsa -t rsa -b 4096 -N '' #where the file name is id_rsa the type of encryption is rsa the bit lenght is 4096 and -N means no passphrase

cat << EOF
#################################################
Setting up SSH KEYS
#################################################
EOF
sleep 2

#################################################
#The line below uses regex to match the pattern 
#called AuthorizedKeysFile in the file
#and globally searches for its comment via the g, 
#when the comment in the files is found at the the start 
#of the string via the /^#/ it is substituted for an 
#uncomment hence the extra /
#check https://stackoverflow.com/questions/24889346/sed-how-to-uncomment-a-line-that-contains-a-specific-string-inline-editing/24889374
#for more detials
#################################################
sudo sed -i '/AuthorizedKeysFile/s/^#//g' /etc/ssh/sshd_config
touch ~/.ssh/authorized_keys
sudo chmod 600 ~/.ssh/authorized_keys

Windows_suggested_copy_path='C:\Users\$env:UserName\Desktop'

cat << EOF
#################################################
Run the folliwng 
commands in power shell to obtian the private key 
needed to login to this host
pscp.exe $(whoami)@$IPADDR:/home/$(whoami)/.ssh/id_rsa $Windows_suggested_copy_path
This will copy the puplic key to the desktop
rember to increse the bit lenght in putty-gen 
if you are using it becuase by deafult it will 
create the ppk file to 2048 bits
#################################################
EOF
sleep 10

cat << EOF
#################################################
Run the folliwng 
commands in power shell to obtian the public key 
needed to login to this host
pscp.exe $(whoami)@$IPADDR:/home/$(whoami)/.ssh/id_rsa.pub $Windows_suggested_copy_path
This will copy the private key to the desktop
remember to chnage the key lenght to 4096 in 
putty gen
#################################################
EOF
sleep 10

cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys_Backup
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
echo 'restarting SSH Deamon'
sudo service ssh restart

}

configure_BIND () {
cat << EOF
#################################################
configuring DNS FORWARDER
#################################################
EOF

sleep 2
cat << EOF
#################################################
make sure to uncomment the // from the forwarders 
section otherwise it wont work
#################################################
EOF
sleep 5

DNS_FORWARDER_CONF="/etc/bind/named.conf.options"
DNS_OUTBOUND_SERVER1="194.168.4.100"
DNS_OUTBOUND_SERVER2="194.168.8.100"
ROUTER_IP_FORWARDING="10.0.0.254"

sed -i 's#//##g' $DNS_FORWARDER_CONF #this means subsitute the // in the script globally via /g via a literal string match (represented by the #) for nothing 
#intrugeinly this works despite there being no // like in normal regex

sudo cp $DNS_FORWARDER_CONF $DNS_FORWARDER_CONF.bak
sudo sed -i "15i $DNS_OUTBOUND_SERVER1;" $DNS_FORWARDER_CONF
sudo sed -i "16i $DNS_OUTBOUND_SERVER2;" $DNS_FORWARDER_CONF
sudo sed -i "17i $ROUTER_IP_FORWARDING;" $DNS_FORWARDER_CONF
sudo vi $DNS_FORWARDER_CONF
sudo named-checkconf

cat <<EOF
if above works current DNS nameservers for virgin are as follows
Domain Name Server	
194.168.4.100
194.168.8.100
Ours
10.0.0.254
EOF


cat << EOF
#################################################
configuring forward zone DNS LOCAL FILE
#################################################
EOF

sleep 2
DNS_LOCAL_CONF="/etc/bind/named.conf.local"
CONFIG_FILE_FOR_VJCLOUD_LOCAL_1='"/etc/bind/db.vjcloud.local"'
For_Zone='"vjcloud.local."'
sudo cp $DNS_LOCAL_CONF $DNS_LOCAL_CONF.bak
sudo sed -i "8i zone "$For_Zone" { " $DNS_LOCAL_CONF
sudo sed -i "9i type master;" $DNS_LOCAL_CONF
sudo sed -i "10i file "$CONFIG_FILE_FOR_VJCLOUD_LOCAL_1";" $DNS_LOCAL_CONF
sudo sed -i "11i };" $DNS_LOCAL_CONF
sudo vi $DNS_LOCAL_CONF

cat << EOF
#################################################
configuring reverse zone DNS LOCAL FILE
#################################################
EOF

sleep 2
Rev_Zone='"253.0.0.10.in-addr.arpa."'
REV_ZONE_1='"/etc/bind/db.253.0.0.10.zone"'
sudo sed -i "12i zone="$Rev_Zone" { " $DNS_LOCAL_CONF
sudo sed -i "13i type master;" $DNS_LOCAL_CONF
sudo sed -i "14i file "$REV_ZONE_1";" $DNS_LOCAL_CONF
sudo sed -i "15i };" $DNS_LOCAL_CONF
sudo vi $DNS_LOCAL_CONF

cat << EOF
#################################################
configuring reverse lookup zone file DNS DATABASE FILE
#################################################
EOF

DB_DEF="/etc/bind/db.empty"
REV_ZONE="/etc/bind/db.253.0.0.10.zone"
sudo cp $DB_DEF $REV_ZONE
sudo sed -i "s/localhost/vjcloud\.local/g" $REV_ZONE #the \ esapces the . othgerwise its treated as regex and the g means global
sudo sed -i "14 a	IN	NS	dns.vjcloud.local." $REV_ZONE
sudo sed -i "15 a 253	IN	PTR	dns.vjcloud.local." $REV_ZONE
sudo echo "please update the serial number and the email address to get the system working to confirm with rfc this should be todays date otherwise you can ony edit the file 99 times it dosn't like 100"
sudo echo "the new serial part will soon be replaced via a script"
sleep 4
#sudo vi $REV_ZONE

cat << EOF
#################################################
checking reverse lookup zone config file and permissions
#################################################
EOF

echo "checking to see if zone can be loaded"
sudo named-checkzone 253.0.0.10.in-addr.arpa.  $REV_ZONE 
sleep 2


cat << EOF
#################################################
checking forward lookup zone config file and permissions
#################################################
EOF

cat $DNS_LOCAL_CONF 
ls -l $DNS_LOCAL_CONF
sudo named-checkconf -v $DNS_LOCAL_CONF

cat << EOF
#################################################
configuring forward lookup zone file DNS DATABASE FILE
#################################################
EOF

CONFIG_FILE_FOR_VJCLOUD_LOCAL="/etc/bind/db.vjcloud.local"

sleep 2
sudo cp $DB_DEF $CONFIG_FILE_FOR_VJCLOUD_LOCAL
sudo sed -i "s/localhost/vjcloud\.local/g" $CONFIG_FILE_FOR_VJCLOUD_LOCAL
sudo sed -i "14 a vjcloud.local.	IN	NS	dns.vjcloud.local." $CONFIG_FILE_FOR_VJCLOUD_LOCAL
sudo sed -i "15 a gw		IN	A	10.0.0.254" $CONFIG_FILE_FOR_VJCLOUD_LOCAL
sudo sed -i "16 a dns	IN	A	10.0.0.253" $CONFIG_FILE_FOR_VJCLOUD_LOCAL
sudo sed -i "17 a jira	IN	A	10.0.0.34" $CONFIG_FILE_FOR_VJCLOUD_LOCAL
sudo sed -i "18 a nextcloud	IN	A	10.0.0.23" $CONFIG_FILE_FOR_VJCLOUD_LOCAL
sudo sed -i "20 a jenkins	IN	A	10.0.0.16" $CONFIG_FILE_FOR_VJCLOUD_LOCAL
sudo sed -i "21 a ansible	IN	A	10.0.0.40" $CONFIG_FILE_FOR_VJCLOUD_LOCAL
sudo sed -i "22 a dccomp	IN	A	10.0.0.5" $CONFIG_FILE_FOR_VJCLOUD_LOCAL
sudo sed -i "23 a gitlab	IN	A	10.0.0.20" $CONFIG_FILE_FOR_VJCLOUD_LOCAL

echo "please update the serial number and the email address to get the system working to confirm with rfc this should be todays date otherwise you can ony edit the file 99 times it dosn't like 100"
echo the new serial part will soon be replaced via a script
sleep 4
sudo vi $CONFIG_FILE_FOR_VJCLOUD_LOCAL


cat << EOF
#################################################
checking zone file to see if the serial can be loaded
#################################################
EOF

sudo named-checkzone vjcloud.local. $CONFIG_FILE_FOR_VJCLOUD_LOCAL

cat << EOF
#################################################
checking file permissions for file $CONFIG_FILE_FOR_VJCLOUD_LOCAL
#################################################
EOF

ls -l $CONFIG_FILE_FOR_VJCLOUD_LOCAL

sleep 5

cat << EOF
so an FQDN is made up of the hostname and the domain name and this is called FQDN
but in their separate parts they are hostname.domain
your domain is
local
hostname
vjcloud
FQDN = hostname+domain = vjcloud.local

so in our case for this config is
dc@vjcloud:~$ hostname -s
vjcloud

dc@vjcloud:~$ hostname -f
vjcloud.local

dc@vjcloud:~$ hostname -d
local

test
dig @10.0.0.253 -t any jira.vjcloud.local
EOF

sleep 5

echo "vjcloud" > /etc/hostname #this is the hotname of the pc
sudo sed -i "2 a 10.0.0.253      vjcloud.local   vjcloud" /etc/hosts

vi /etc/hostname
vi /etc/hosts


cat << EOF
#################################################
Enabling and checking BIND9 config
#################################################
EOF

sleep 2
sudo service bind9 start
sudo systemctl enable bind9.service
sudo systemctl reload bind9.service
sudo systemctl status bind9.service
#sudo rcnamed restart avalible on suse
sleep 5

cat << EOF
#################################################
checking BIND9 syslog
#################################################
EOF

tail $BIND9_SYSLOG
sleep 5


cat << EOF
#################################################
checking file $VAR_LOG_MESSAGES
#################################################
EOF

tail $VAR_LOG_MESSAGES
sleep 10

cat << EOF
#################################################
checking resolv.conf file which is used by other
computer for DNS resoultion
#################################################
EOF

cat /etc/resolv.conf

cat << EOF
#################################################
Restarting DNS Zone
#################################################
EOF

sudo rndc reload vjcloud.local.
sudo rndc reload 253.0.0.10.in-addr.arpa.


cat << EOF
#################################################
checking DNS hosts
look for (3NXS) in output to suggest
a resolution problem
#################################################
EOF

dig @10.0.0.253 -t any vjcloud.local
dig @10.0.0.253 -t any jira.vjcloud.local
dig @10.0.0.253 -t any nextcloud.vjcloud.local
dig @10.0.0.253 -t any jenkins.vjcloud.local
dig @10.0.0.253 -t any ansible.vjcloud.local
dig @10.0.0.253 -t any gitlab.vjcloud.local
dig @10.0.0.253 -t any dccomp.vjcloud.local

host vjcloud.local
host jira.vjcloud.local
host nextcloud.vjcloud.local 
host jenkins.vjcloud.local
host ansible.vjcloud.local
host gitlab.vjcloud.local
host dccomp.vjcloud.local

ping -c 10 vjcloud.local
ping -c 10 jira.vjcloud.local
ping -c 10 nextcloud.vjcloud.local
ping -c 10 jenkins.vjcloud.local
ping -c 10 ansible.vjcloud.local
ping -c 10 gitlab.vjcloud.local
ping -c 10 dccomp.vjcloud.local
ping -c 10 google.com 

sleep 30

cat << EOF
#################################################
Checking DNS zone file
#################################################
EOF
cat $DNS_LOCAL_CONF

sleep 20

cat << EOF
#################################################
NOTE: Need to update the serial number for each config change 
also need to edit the resolv.conf file to the make the zone records visible on each comp 
then restart bind
#################################################
EOF

cat << EOF
#################################################
checking date and time config for logging
#################################################
EOF
timedatectl
cat /etc/timezone
date
sudo hwclock --show


cat << EOF
#################################################
creating shortcuts to edit forward 
and reverse lookup zone
and adding zone configuration 
#################################################
EOF
sleep 3
ln -s $CONFIG_FILE_FOR_VJCLOUD_LOCAL forwardzone
ln -s $REV_ZONE reversezone
ln -s $DNS_FORWARDER_CONF forwarder
ln -s $DNS_LOCAL_CONF zoneconfig

cat << EOF
#################################################
NOTE: Test this config out by changing the network
adapter setting in windows to point to the
IPV4 addr of $IPADDR then try to resolve the
entries for:
nextcloud.vjcloud.local
jira.vjcloud.local
jenkins.vjcloud.local
#################################################
EOF


cat << EOF
#################################################
checking the order in which hosts are resolved
either via DNS or /etc/hosts for the machine
#################################################
EOF

CHECK="grep -E 'files dns' /etc/nsswitch.conf"
if [ "$CHECK" ]; then

cat <<EOF
################################################# 
The host is doing lookups via DNS meaning that 
they are resolving through the /etc/resolve.conf
#################################################
EOF

else 

cat <<EOF
################################################# 
it seems like hosts are resolved in  a diffrent
way showing output below
#################################################
EOF

cat /etc/nsswitch.conf

fi

sleep 20
}


BIND_DNS_RECCURSION () {
cat << EOF
#################################################
This part of the scirpt enables caching in the DNS webserver
by looking to 10.0.0.254 if the DNS server dosen't
understand quieres from clients
but 10.0.0.253 will cache the request and store the reponse
it recives from 10.0.0.1 
for more info see 
https://www.digitalocean.com/community/tutorials/how-to-configure-bind-as-a-caching-or-forwarding-dns-server-on-ubuntu-14-04
#################################################
EOF


cat << EOF >>$DNS_LOCAL_OPTIONS.bak
acl goodclients {
    192.0.2.0/8;
    localhost;
    localnets;
};

options {
        directory "/var/cache/bind";
        recursion yes;
        allow-query { goodclients; };

        // If there is a firewall between you and nameservers you want
        // to talk to, you may need to fix the firewall to allow multiple
        // ports to talk.  See http://www.kb.cert.org/vuls/id/800113

        // If your ISP provided one or more IP addresses for stable
        // nameservers, you probably want to use them as forwarders.
        // Uncomment the following block, and insert the addresses replacing
        // the all-0's placeholder.

         forwarders {
                //0.0.0.0;
                194.168.4.100;
                194.168.8.100;
                10.0.0.254;
         };
         forward only;

        //========================================================================
        // If BIND logs error messages about the root key being expired,
        // you will need to update your keys.  See https://www.isc.org/bind-keys
        //========================================================================
        dnssec-enable yes;
        dnssec-validation yes;

        auth-nxdomain no;    # conform to RFC1035
        listen-on-v6 { any; };
};
EOF

webmin_install () {
    echo "adding web min repository to /etc/apt/sources.list"
    sed -i "57a deb http://download.webmin.com/download/repository sarge contrib" /etc/apt/sources.list
    wget http://www.webmin.com/jcameron-key.asc
    echo "adding gpg key so that the repo becomes trusted"
    sudo apt-key add jcameron-key.asc -y
    sudo apt-get update 
    echo "installing webmin"
    sudo apt-get install webmin -y
}

mv $DNS_LOCAL_OPTIONS.bak  $DNS_LOCAL_OPTIONS
sudo named-checkconf
sudo service bind9 restart
}

Questions () {
read -p "would you to setup the server to run DNS services?[Y/n] : " Install
if [ "$Install" != "n" ]
then 
	networking
	ssl
	BIND
	configure_BIND
	BIND_DNS_RECCURSION
    webmin_install
else
read -p "would you like to setup static netwokring[Y/n] : " Networking
if [ "$Networking" != "n" ]
then
	networking
else 
read -p "would you like to setup SSL[Y/n] : " SSl
if [ "$SSL" != "n" ]
then
	ssl
else
read -p "would you like to install BIND9/DNS[Y/n] : " BIND_ANSWER
if [ "$BIND_ANSWER" != "n" ]
then
	BIND
else 
read -p "would you like to configure BIND9/DNS[Y/n] : "  BINDConf
if [ "$BINDConf" != "n" ]
then
	configure_BIND
fi
fi
fi
fi
fi 
}

cat << EOF
#################################################
BIND/DNS UBUNTU SCRIPT
Please make sure you run this script in Ubuntu
#################################################
EOF
sleep 2

OS_CHECK="grep debian /etc/os-release"

if [ "$OS_CHECK" ]; then 
Questions
else
cat << EOF
#################################################
The Operating system that you have is
not currently supported by this script
check back in the futre for updates
I plan on supporting Centos with this script
later on
#################################################
EOF
sleep 10 
fi
exit 0

