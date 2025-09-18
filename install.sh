### Quick Script to Install the log analysis tool

## Check for prereqs
echo "Checking for prereqs:"

echo -n "rkhunter "
command -v rkhunter > /dev/null 2>&1 || { echo >&2 "[BAD] rkhunter not installed, do sudo apt install rkhunter"; exit 1; }
echo "[OK]"

echo -n "fail2ban "
command -v fail2ban-server > /dev/null 2>&1 || { echo >&2 "[BAD] fail2ban not installed, do sudo apt install fail2ban"; exit 1; }
echo "[OK]"

## Check for running fail2ban
echo -n "Checking for running fail2ban "
pgrep fail2ban > /dev/null 2>&1 || { echo >&2 "[BAD] fail2ban does not appear to be running, please configure"; exit 1; }
echo "[OK]"

## Check for log file existence
echo -n "Checking for /var/log/auth.log "
test -f /var/log/auth.log || { echo >&2 "[BAD] log does not exist"; exit 1; }
echo "[OK]"

echo -n "Checking for /var/log/auth.log.1 "
test -f /var/log/auth.log.1 || { echo >&2 "[BAD] log does not exist"; exit 1; }
echo "[OK]"

echo -n "Checking for /var/log/fail2ban.log "
test -f /var/log/fail2ban.log || { echo >&2 "[BAD] log does not exist"; exit 1; }
echo "[OK]"

echo -n "Checking for /var/log/fail2ban.log.1 "
test -f /var/log/fail2ban.log.1 || { echo >&2 "[BAD] log does not exist"; exit 1; }
echo "[OK]"

echo -n "Install systemd reporting"
install -Dm 0755 -T ./sshd_report.sh /usr/local/bin/sshd_report
install -Dm 0755 -T ./sshd_report_sendmail.sh /usr/local/bin/sshd_report_sendmail
install -Dm 0755 -T ./systemd/sshd-report.conf /etc/conf.d/sshd-report
install -Dm 0644 -t /etc/systemd/system ./systemd/sshd-report@.{service,timer}

systemctl enable --now sshd-report@daily.timer
echo "[OK]"

## All Done
echo "Complete!"
