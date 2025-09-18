#!/bin/bash
set -e

HELP='false'
SENDMAILFLAG='false'
RKHUNT='false'

usage() {
	echo "Usage: sshd_report [-hmor] EMAIL_TO EMAIL_FROM"
        echo "basic SSHD email log report"
	echo "   -h  help"
	echo "   -m  email formatting (include header/HTML junk)"
	echo "   -r  run rkhunter"
}

##ARGUMENT HANDLING
while getopts 'hmr' flag; do
  case "${flag}" in
    h) HELP='true' ;;
    m) SENDMAILFLAG='true' ;;
    r) RKHUNT='true' ;;
  esac
  shift
done

if [ $# -ne 2 ]; then
	echo "wrong args: $*"
	usage
	exit 2
fi

EMAIL_FROM=$1
EMAIL_TO=$2

##HELP
if [ "$HELP" = "true" ]; then
	usage
	exit 0
fi


##START RKHUNTER IN BACKGROUND
if [ "$RKHUNT" = "true" ]; then
	sudo rkhunter --check --enable all -q --sk --summary > rkhunt.log &
	PID=$!
fi

##HTML HEADER JUNK
if [ "$SENDMAILFLAG" = "true" ]; then
	echo "To: $EMAIL_TO"
	echo "From: $EMAIL_FROM"
	echo "Subject: Daily Log Analysis"
	echo "MIME-Version: 1.0"
	echo "Content-Type: text/html"
	echo "Content-Disposition: inline"
	echo "<html>"
	echo "<body>"
	echo "<pre style=\"font: monospace\">"
fi

# Create a Logfile with the last day
yesterday=$(date --date='1 days ago' +"%F")
today=$(date +"%F")
journalctl --since=$yesterday --until=$today --identifier=sshd | tail -n +2 > day.log

# How many hours the logs cover
echo "LOG ANALYSIS:"
echo -n "Analyzing logs from "
head -n 1 day.log | grep -a -P -o "^(\S+\s+\S+\s+\S+)" | tr -d '\n'	# Start
echo -n " to "
tail -n 1 day.log | grep -a -P -o "^(\S+\s+\S+\s+\S+)" 			# End
echo ""

##SUCCESS SECTION
# Grab successful logins and put them in a file
grep -a "Accepted" day.log > successful_auths.log || true

# How many successful logins there were
successful_auths_count=$(wc -l < successful_auths.log | tr -d '\n')

# How many successful unique usernames there were
successful_users_count=$(grep -oP "for \K\S+" successful_auths.log | sort | uniq | wc -l | tr -d '\n')

# How many successful unique IPs there were
successful_ips_count=$(grep -oP "from \K[0-9\.]+" successful_auths.log | sort | uniq | wc -l | tr -d '\n')

# Print words
printf "There were %d successful login(s) from %d account(s) and %d IP address(es)\n" "$successful_auths_count" "$successful_users_count" "$successful_ips_count"

# Skip printing "Top users" if nobody logged in
if [ "$successful_auths_count" != "0" ]; then

	# What were the top successful usernames
	echo "The top username(s) were:"
	grep -a -oP "for \K(\S+)" successful_auths.log | sort | uniq -c | sort -nr | head -n 5 | sed -E 's/^( +)/   /g'

	# What were the top successful IPs
	echo "The top IP(s) were:"
	grep -a -oP "from \K(\S+)" successful_auths.log | sort | uniq -c | sort -nr | head -n 5 > successful_ips.log

	while read line; do
		line_ip=$(echo "$line" | cut -d " " -f 2)
		echo "$line_ip"
	done < successful_ips.log

	echo ""
else
	echo ""
fi


##FAIL2BAN PREP
# Create a Logfile with the last day
grep -a "`date --date='1 days ago' +"%F"`" /var/log/fail2ban.log* > fail2ban_day.log || true

##FAILURE SECTION
# Grab failed logins and put them in a file
grep -a "Disconnected" day.log | grep -a "preauth" > failed_auths.log

# How many failed logins there were
failed_auths_count=$(wc -l < failed_auths.log | tr -d '\n')

# How many failed unique usernames there were
failed_users_count=$(grep -a -oP "user \K\S+" failed_auths.log | sort | uniq | wc -l | tr -d '\n')

# How many failed unique IPs there were
failed_ips_count=$(grep -a -oP "\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b" failed_auths.log | sort | uniq | wc -l | tr -d '\n')

# Print words
printf "There were %d failed login(s) from %d account(s) and %d IP address(es)\n" "$failed_auths_count" "$failed_users_count" "$failed_ips_count"


# Skip printing "Top users" if nobody logged in
if [ "$failed_auths_count" != "0" ]; then

	# What were the top failed usernames
	echo "The top username(s) were:"
	grep -a -oP "user \K\S+" failed_auths.log | sort | uniq -c | sort -nr | sed -E 's/^( +)/   /g' > failed_usernames.log
	cat failed_usernames.log | head -n 5

	# What were the top failed IPs
	echo "The top IP(s) were:"
	grep -a -oP "\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b" failed_auths.log | sort | uniq -c | sort -nr | head -n 5 > failed_ips.log

	while read line; do
	    line_ip=$(echo "$line" | grep -a -oP "\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b")

		if grep -a -q "$line_ip" fail2ban_day.log; then
			banned="BANNED"
		else
			banned=""
		fi

		printf "   %-18s: %s\n" "$line" "$banned"
	done < failed_ips.log

	echo ""

	# Print failed logins to real users
	while read line; do
		if grep -a -oP "^\w+" /etc/passwd | grep -a -q "^"`echo "$line" | cut -d " " -f 2`"$"; then
			count=$(echo "$line" | grep -a -oP "^\w+")
			user=$(echo "$line" | grep -a -oP "\w+$")
			printf "%d attempts on real account %s\n" "$count" "$user"
		fi
	done < failed_usernames.log
	echo ""

else
	echo ""
fi


##FAIL2BAN SECTION
# Count number of bans
fail2ban_bans=$(grep -a "] Ban" fail2ban_day.log | wc -l)

# Print words
echo "FAIL2BAN ANALYSIS:"
printf "Blocked %d IP address(es)\n\n" "$fail2ban_bans"


##RKHUNTER SECTION
# Wait for rkhunter and print report
if [ "$RKHUNT" = "true" ]; then
	echo -n "RKHUNTER RESULTS:"
	wait $PID
	cat rkhunt.log | head -n 11
fi

##HTML END STUFF
if [ "$SENDMAILFLAG" = "true" ]; then
	echo "</pre>"
	echo "</body>"
	echo "</html>"
fi

##CLEAN UP
rm -f day.log
rm -f successful_auths.log
rm -f successful_ips.log
rm -f failed_auths.log
rm -f failed_ips.log
rm -f failed_usernames.log
rm -f fail2ban_day.log
rm -f rkhunt.log
