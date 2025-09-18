#! /usr/bin/env bash -e
MAIL_FROM=$1
MAIL_TO=$2
sshd_report -m ${MAIL_FROM} "${MAIL_TO}" | sendmail -t
