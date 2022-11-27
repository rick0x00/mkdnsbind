#!/bin/bash


domain="example.com.br"
hostname=$(hostname)
hostnameips=$(hostname -I)
hostnamefisrtipv4=$(hostname -I | cut -d" " -f1)
reversehostnamefisrtipv4=$(echo $hostnamefisrtipv4 | cut -d"." -f4).$(echo $hostnamefisrtipv4 | cut -d"." -f3).$(echo $hostnamefisrtipv4 | cut -d"." -f2).$(echo $hostnamefisrtipv4 | cut -d"." -f1)
endhostnamefisrtipv4=$(echo $hostnamefisrtipv4 | cut -d"." -f4)

echo "Install BIND"
apt update
apt install -y bind9 bind9utils bind9-doc

echo "Configure /etc/hosts"

echo "Configure /etc/hosts"
cp /etc/hosts /etc/hosts.bkp_$(date --iso-8601='s')
echo "" >> /etc/hosts
echo "# --- START DNS MAPPING ---" >> /etc/hosts
echo "$hostnamefisrtipv4 $hostname.$domain" >> /etc/hosts
echo "# --- BEGIN DNS MAPPING ---" >> /etc/hosts
echo "" >> /etc/hosts


echo "Configure /etc/bind/named.conf.local"
echo "Specify Local Zone Files (DBs) directives"
cp /etc/bind/named.conf.local /etc/bind/named.conf.local.bkp_$(date --iso-8601='s')

echo '
// --- START ORGANIZATION ZONES ---
// Forward Lookup Zone
zone '"$domain"' {
	type master;
	file "'"/etc/bind/db.$domain"'";
};

// Reverse Lookup Zone
zone '"$reversehostnamefisrtipv4.in-addr.arpa"' {
	type master;
	file "'"/etc/bind/db.$reversehostnamefisrtipv4"'";
};
// --- BEGIN ORGANIZATION ZONES ---
' >> /etc/bind/named.conf.local


echo "Making Zone files"
echo '
;
; BIND data file for local loopback interface
;
$TTL	604800
@	IN	SOA'"	$hostname.$domain. root.$domain. "'(
			      2		; Serial
			 604800		; Refresh
			  86400		; Retry
			2419200		; Expire
			 604800 )	; Negative Cache TTL
;'"
$domain.	IN	NS	$hostname.$domain.
$domain.	IN	A	$hostnamefisrtipv4

$hostname	IN	A	$hostnamefisrtipv4

"'' > /etc/bind/db.$domain

echo ';
; BIND reverse data file for local loopback interface
;
$TTL	604800
@	IN	SOA'"	$hostname.$domain. root.$domain. "'(
			      1		; Serial
			 604800		; Refresh
			  86400		; Retry
			2419200		; Expire
			 604800 )	; Negative Cache TTL
;'"
	IN	NS	$domain.
$endhostnamefisrtipv4	IN	PTR $hostname.$domain.
"'' > /etc/bind/db.$reversehostnamefisrtipv4

echo "End Configurations"
systemctl enable --now bind9
systemctl restart bind9
systemctl status bind9