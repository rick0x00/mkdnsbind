#!/bin/bash


domain="example.com.br"
hostname=$(hostname)
hostnameips=$(hostname -I)
hostnamefisrtipv4=$(hostname -I | cut -d" " -f1)
reversehostnamefisrtipv4=$(echo $hostnamefisrtipv4 | cut -d"." -f3).$(echo $hostnamefisrtipv4 | cut -d"." -f2).$(echo $hostnamefisrtipv4 | cut -d"." -f1)
endhostnamefisrtipv4=$(echo $hostnamefisrtipv4 | cut -d"." -f4)
serialdate=$(date +'%Y%m%d')

echo "Establishing Temporary Good DNS"
cp /etc/resolv.conf /etc/resolv.conf.bkp_$(date --iso-8601='s')
echo "nameserver 8.8.8.8" > /etc/resolv.conf

echo "Install BIND"
apt update
apt install -y bind9 bind9utils bind9-doc

echo "Establishing Localhost DNS"
cp /etc/resolv.conf /etc/resolv.conf.bkp_$(date --iso-8601='s')
echo "nameserver 127.0.0.1
search localhost" > /etc/resolv.conf

echo "Configure /etc/hosts"
cp /etc/hosts /etc/hosts.bkp_$(date --iso-8601='s')
echo "" >> /etc/hosts
echo "# --- START DNS MAPPING ---" >> /etc/hosts
echo "$hostnamefisrtipv4 $hostname.$domain" >> /etc/hosts
echo "# --- BEGIN DNS MAPPING ---" >> /etc/hosts
echo "" >> /etc/hosts

echo "Making Workdir"
mkdir -p /var/lib/bind/$domain/db /var/lib/bind/$domain/keys
chown root:bind -R /var/lib/bind/*
chmod 770 -R /var/lib/bind/*


echo "Making Zone files"
echo '
;
; BIND data file for local loopback interface
;
$TTL	604800
@	IN	SOA'"	$hostname.$domain. root.$domain. "'(
		       '"$serialdate"'		; Serial
			 604800		; Refresh
			  86400		; Retry
			2419200		; Expire
			 604800 )	; Negative Cache TTL
;'"
$domain.	IN	NS	$hostname.$domain.
$domain.	IN	A	$hostnamefisrtipv4

$hostname	IN	A	$hostnamefisrtipv4

" > /var/lib/bind/$domain/db/db.$domain

echo ';
; BIND reverse data file for local loopback interface
;
$TTL	604800
@	IN	SOA'"	$hostname.$domain. root.$domain. "'(
		       '"$serialdate"'		; Serial
			 604800		; Refresh
			  86400		; Retry
			2419200		; Expire
			 604800 )	; Negative Cache TTL
;'"
	IN	NS	$domain.
$endhostnamefisrtipv4	IN	PTR $hostname.$domain.
" > /var/lib/bind/$domain/db/db.$reversehostnamefisrtipv4

echo "Implement DNSSEC"
# Create our initial keys
cd /var/lib/bind/$domain/keys/
#sudo dnssec-keygen -a RSASHA256 -b 2048 -f KSK "$domain"
#sudo dnssec-keygen -a RSASHA256 -b 1280 "$domain"

sudo dnssec-keygen -a NSEC3RSASHA1 -b 2048 -n ZONE $domain
sudo dnssec-keygen -f KSK -a NSEC3RSASHA1 -b 4096 -n ZONE $domain


# Set permissions so group bind can read the keys
chgrp bind /var/lib/bind/$domain/keys/*
chmod g=r,o= /var/lib/bind/$domain/keys/*
#sudo dnssec-signzone -S -z -o "$domain" "/var/lib/bind/$domain/db/db.$domain"
#sudo dnssec-signzone -S -z -o "$domain" "/var/lib/bind/$domain/db/db.$reversehostnamefisrtipv4"
#sudo chmod 644 /etc/bind/*.signed

# configure named.conf.options
cp /etc/bind/named.conf.options /etc/bind/named.conf.options.bkp_$(date --iso-8601='s')

echo 'options {
	directory "/var/cache/bind";
	dnssec-enable yes;
	dnssec-validation auto;
	listen-on-v6 { any; };
};
' > /etc/bind/named.conf.options

echo "Configure /etc/bind/named.conf.local"
echo "Specify Local Zone Files (DBs) directives"
cp /etc/bind/named.conf.local /etc/bind/named.conf.local.bkp_$(date --iso-8601='s')

echo '
// --- START ORGANIZATION ZONES ---
// Forward Lookup Zone
zone '"$domain"' {
	type master;
	file "'"/var/lib/bind/$domain/db/db.$domain"'";
	key-directory "'"/var/lib/bind/$domain/keys/"'";
	auto-dnssec maintain;
	inline-signing yes;
	serial-update-method increment;
};

// Reverse Lookup Zone
zone '"$reversehostnamefisrtipv4.in-addr.arpa"' {
	type master;
	file "'"/var/lib/bind/$domain/db/db.$reversehostnamefisrtipv4"'";
};
// --- BEGIN ORGANIZATION ZONES ---
' > /etc/bind/named.conf.local


echo "End Configurations"
systemctl enable --now bind9
systemctl restart bind9
systemctl status bind9;

echo "Show DS code, Keytag and Digest"
d=$(echo $domain); dig @127.0.0.1 +norecurse "$d". DNSKEY | sudo dnssec-dsfromkey -f - "$d" | head -1
