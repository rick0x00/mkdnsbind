#!/bin/bash

dnstype="master"
masterdnsipv4="192.168.0.2"
slavednsipv4="192.168.0.3"
domain="example.com.br"

hostname=$(hostname)
hostnameips=$(hostname -I)
hostnamefisrtipv4=$(echo "$masterdnsipv4" | cut -d" " -f1)
reversehostnamefisrtipv4=$(echo $hostnamefisrtipv4 | cut -d"." -f3).$(echo $hostnamefisrtipv4 | cut -d"." -f2).$(echo $hostnamefisrtipv4 | cut -d"." -f1)
endhostnamefisrtipv4=$(echo $hostnamefisrtipv4 | cut -d"." -f4)
endbyteipv4masterdns=$(echo $masterdnsipv4 | cut -d"." -f4)
endbyteipv4slavedns=$(echo $slavednsipv4 | cut -d"." -f4)
serialdate=$(date +'%Y%m%d')

echo "Establishing Temporary Good DNS"
cp /etc/resolv.conf /etc/resolv.conf.bkp_$(date --iso-8601='s')
echo "nameserver 8.8.8.8" > /etc/resolv.conf

echo "Install BIND"
apt update
apt install -y bind9 bind9utils bind9-doc dnsutils

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

if [ $dnstype = "master" ]; then
	echo "Making Zone files"
echo ';
; BIND data file for local loopback interface
;
$TTL	604800
@	IN	SOA'"	ns1.$domain. root.$domain. "'(
			'"$serialdate"'		; Serial
			604800		; Refresh
			86400		; Retry
			2419200		; Expire
			604800 )	; Negative Cache TTL
;'"
			IN	NS	ns1.$domain.
			IN	NS	ns2.$domain.

ns1			IN	A	$masterdnsipv4
ns2			IN	A	$slavednsipv4	

$hostname	IN	A	$hostnamefisrtipv4

" > /var/lib/bind/$domain/db/db.$domain

echo ';
; BIND reverse data file for local loopback interface
;
$TTL	604800
@	IN	SOA'"	ns1.$domain. root.$domain. "'(
			'"$serialdate"'		; Serial
			604800		; Refresh
			86400		; Retry
			2419200		; Expire
			604800 )	; Negative Cache TTL
;'"
			IN	NS	ns1.$domain.
			IN	NS	ns2.$domain.

$endbyteipv4masterdns			IN	PTR ns1.$domain.
$endbyteipv4slavedns			IN	PTR ns2.$domain.

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
fi


echo "configure named.conf.options"
cp /etc/bind/named.conf.options /etc/bind/named.conf.options.bkp_$(date --iso-8601='s')

if [ $dnstype = "master" ]; then
	echo 'options {
		directory "/var/cache/bind";
		dnssec-enable yes;
		dnssec-validation auto;
		listen-on { any; };
		listen-on-v6 { any; };
		allow-transfer {
			'"$slavednsipv4"';
		};
		allow-notify {
			'"$slavednsipv4"';
		};
		masterfile-format text;
		version "RR DNS Server";
	};
	' > /etc/bind/named.conf.options
elif [ $dnstype = "slave" ]; then
	echo 'options {
		directory "/var/cache/bind";
		dnssec-enable yes;
		dnssec-validation auto;
		listen-on { any; };
		listen-on-v6 { any; };
		allow-transfer { none; };
		masterfile-format text;
		version "RR DNS Server";
	};
	' > /etc/bind/named.conf.options
fi

echo "Configure /etc/bind/named.conf.local"
echo "Specify Local Zone Files (DBs) directives"
cp /etc/bind/named.conf.local /etc/bind/named.conf.local.bkp_$(date --iso-8601='s')

if [ $dnstype = "master" ]; then
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
elif [ $dnstype = "slave" ]; then
	echo '
	// --- START ORGANIZATION ZONES ---
	// Forward Lookup Zone
	zone '"$domain"' {
		type slave;
		file "'"/var/lib/bind/$domain/db/db.$domain.signed"'";
		masters { '"$masterdnsipv4"'; };
		allow-notify { '"$masterdnsipv4"'; };
	};

	// Reverse Lookup Zone
	zone '"$reversehostnamefisrtipv4.in-addr.arpa"' {
		type slave;
		file "'"/var/lib/bind/$domain/db/db.$reversehostnamefisrtipv4.signed"'";
		masters { '"$masterdnsipv4"'; };
		allow-notify { '"$masterdnsipv4"'; };
	};
	// --- BEGIN ORGANIZATION ZONES ---
	' > /etc/bind/named.conf.local
fi

echo "End Configurations"
systemctl enable --now bind9
systemctl restart bind9
systemctl status bind9;

echo "Show DS code, Keytag and Digest"
d=$(echo $domain); dig @127.0.0.1 +norecurse "$d". DNSKEY | sudo dnssec-dsfromkey -f - "$d" | head -1
