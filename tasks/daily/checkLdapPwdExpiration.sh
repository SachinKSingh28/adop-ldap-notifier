#!/bin/bash

#====================================================================
# Script for OpenLDAP with ppolicy overlay
#
# Does searches on LDAP directory to determine which user passwords
# came to expiration. If so, sends mails to concerned users.
#
# Tested on :
#   - GNU/Linux platform ;
#   - SunOS 8.5 platform ;
#
# Dependences :
#   - gawk
#   - ldapsearch
#   - curl
#
# Copyright (C) 2008 Clement OUDOT
# Copyright (C) 2007 Thomas CHEMINEAU
# Copyright (C) 2009 LTB-project.org
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# GPL License: http://www.gnu.org/licenses/gpl.txt
#
#====================================================================

#====================================================================
# Changelog
#====================================================================
# Version 0.3 (03/2010):
# - #295 fixed:
#   Add a parameter to specify the search scope
#   Get compatibility with cut behaviour on SUSE system
# Version 0.2 (08/2008):
# - Use zulu time (GMT) for currentTime
# - Split mail command parameters (binary and subject)
# - Add script statitics to STDOUT
# - Add debug info to STDERR
# - Use ppolicy warning time for mail delay if provided
# - Manage no default ppolicy case (just per-user ppolicies)
# - LDAP user attributes are now configurable
# - Jump to next user if no password change date or no ppolicy
# LIMIT: multi-lined DN causes errors
# TODO: use GMT time for SunOS and test the script for this OS
# Author: Clement OUDOT (LINAGORA)
#
# Version 0.1 (2007):
# - First version
# Author: Thomas CHEMINEAU (LINAGORA)
# Version 0.2 (2017):
# - Second version
# Author: Sachin K Singh
#====================================================================


#====================================================================
# Configuration
#====================================================================

#
# LDAP host URI
# eg: ldap://localhost:389
#
MY_LDAP_DEFAULT_HOST_URI="ldap://localhost:389"
MY_LDAP_HOSTURI="${LDAP_SERVER:-${MY_LDAP_DEFAULT_HOST_URI}}"

#
# LDAP root DN (optional)
# eg: cn=Manager,dc=example,dc=com
#
MY_LDAP_ROOTDN="${LDAP_USERNAME}"

#
# LDAP root password (optional)
#
MY_LDAP_ROOTPW=${LDAP_PASSWORD}

#
# LDAP default password policy DN
# eg: ou=defaultPasswordPolicy,dc=example,dc=com
# If commented, we suppose there are no default, and only per-user policies
#
MY_LDAP_DEFAULTPWDPOLICYDN="${SLAPD_DEFAULT_POLICY}"

#
# LDAP search base for users
# eg: ou=People,dc=example,dc=com
#
MY_LDAP_SEARCHBASE="${LDAP_USER_BASE_DN}"

#
# LDAP search filter to use to get all users
#
MY_LDAP_SEARCHFILTER="(&(uid=*)(objectClass=inetOrgPerson))"

#
# LDAP search scope to use to get all users
#
MY_LDAP_SEARCHSCOPE="one"

#
# Path to LDAP search binary
#
MY_LDAP_SEARCHBIN="/usr/bin/ldapsearch"

#
# Delay to begin sending adverts
# Comment to use the pwdExpireWarning value of the user's Password Policy
#
#MY_MAIL_DELAY=1296000

#
# LDAP attributes storing user's information
#   NAME: Display name of the user
#   LOGIN: Account ID of the user
#   MAIL: Email of the user
#
MY_LDAP_NAME_ATTR=cn
MY_LDAP_LOGIN_ATTR=uid
MY_LDAP_MAIL_ATTR=mail


#################
# Notification Support
# - mail
# - hipchat
#################
NOTIFIER="${LDAP_EXPIRY_NOTIFIER:=mail}"

#
# Parameters for hipchat
#
HIPCHAT_DEFAULT_SERVER=https://api.hipcat.com
HIPCHAT_SERVER_URL="${HIPCHAT_SERVER_URL:=${HIPCHAT_DEFAULT_SERVER}}"
HIPCHAT_ROOM_ID=${HIPCHAT_ROOM_ID}
HIPCHAT_ROOM_TOKEN=${HIPCHAT_ROOM_TOKEN}

#
# Mail body message, with particular variables :
#   %name : user name
#   %login : user login
#
MY_MAIL_BODY="From: support@example.com\n\n \
        Hi %name,\n\n \
        please change your password.\n\n"

#
# Mail subject
#
MY_MAIL_SUBJECT="Your account will expire soon"

#
# Mail command binary
# Replace mailx by mail for RedHat
#
MY_MAIL_BIN="mail"

#
# Mail command binary
# Replace mailx by mail for RedHat
#
MY_MAINTAINER_EMAIL_ADDRESS="${MAINTAINER_MAIL_ADDRESS}"

#
# Log header format
# Could include unix commands
#
MY_LOG_HEADER="`date +\"%b %e %T\"` `hostname` $0[$$]:"

#
# Path to GAWK (GNU awk) binary
#
MY_GAWK_BIN="/usr/bin/gawk"

#====================================================================
# Functions
#====================================================================

#
# Retrieves date in seconds.
# This function could take one parameter, a time returned by the command
# `date +"%Y %m %d %H %M %S"`. Without parameter, it returns GMT time.
#
getTimeInSeconds() {
        date=0
        os=`uname -s`

        if [ "$1" ]; then
                date=`${MY_GAWK_BIN} 'BEGIN  { \
                        if (ARGC == 2) { \
                                print mktime(ARGV[1]) \
                        } \
                        exit 0 }' "$1"`
        else
                if [ "${os}" = "SunOS" ]; then
                        # Under Sun Solaris, there is no simple way to
                        # retrieve epoch time.
                        # TODO: manage zulu time (GMT)
                        date=`/usr/bin/truss /usr/bin/date 2>&1 | nawk -F= \
                                '/^time\(\)/ {gsub(/ /,"",$2);print $2}'`
                else
                        now=`date +"%Y %m %d %H %M %S" -u`
                        date=`getTimeInSeconds "$now"`
                fi
        fi

        echo ${date}
}

get_policy_attribute() {
        ldap_search="${MY_LDAP_SEARCHBIN} ${ldap_param} -s base"
        ldap_search="${ldap_search} -b ${1}"
        echo ${ldap_search}
}

#====================================================================
# Script
#====================================================================

## Variables initialization
tmp_dir="/tmp/$$.checkldap.tmp"
result_file="${tmp_dir}/res.tmp.1"
buffer_file="${tmp_dir}/buf.tmp.1"
ldap_param="-LLL -H ${MY_LDAP_HOSTURI} -x"
nb_users=0
nb_expired_users=0
nb_warning_users=0
nb_never_expire_users=0
PWD_NO_EXPIRY_USERS=""
PWD_EXPIRED_USERS=""
PWD_WARN_USERS=""

## Some tests
if [ -d ${tmp_dir} ]; then
        echo "Error : temporary directory exists (${tmp_dir})"
        rm -rf ${tmp_dir}
fi
mkdir ${tmp_dir}

if [ ${MY_LDAP_ROOTDN} ]; then
        ldap_param="${ldap_param} -D ${MY_LDAP_ROOTDN} -w ${MY_LDAP_ROOTPW}"
fi

## Performs global search
${MY_LDAP_SEARCHBIN} ${ldap_param} -s ${MY_LDAP_SEARCHSCOPE} \
        -b "${MY_LDAP_SEARCHBASE}" "${MY_LDAP_SEARCHFILTER}" \
        "dn" > ${result_file}

## Loops on results
while read dnStr
do
        # Do not use blank lines
        if [ ! "${dnStr}" ]; then
                continue
        fi

        # Process ldap search
        dn=`echo ${dnStr} | cut -d : -f 2`

        # Increment users counter
        nb_users=`expr ${nb_users} + 1`

        ${MY_LDAP_SEARCHBIN} ${ldap_param} -s base -b "${dn}" \
                ${MY_LDAP_NAME_ATTR} ${MY_LDAP_LOGIN_ATTR} ${MY_LDAP_MAIL_ATTR} pwdChangedTime pwdPolicySubentry \
                > ${buffer_file}

        login=`grep -w "${MY_LDAP_LOGIN_ATTR}:" ${buffer_file} | cut -d : -f 2 \
                | sed "s/^ *//;s/ *$//"`
        name=`grep -w "${MY_LDAP_NAME_ATTR}:" ${buffer_file} | cut -d : -f 2\
                | sed "s/^ *//;s/ *$//"`
        mail=`grep -w "${MY_LDAP_MAIL_ATTR}:" ${buffer_file} | cut -d : -f 2 \
                | sed "s/^ *//;s/ *$//"`
        pwdChangedTime=`grep -w "pwdChangedTime:" ${buffer_file} \
                | cut -d : -f 2 | cut -c 1-15 | sed "s/^ *//;s/ *$//"`
        pwdPolicySubentry=`grep -w "pwdPolicySubentry:" ${buffer_file} \
                | cut -d : -f 2 | sed "s/^ *//;s/ *$//"`
        pwdPolicySubentry=${pwdPolicySubentry:=${MY_LDAP_DEFAULTPWDPOLICYDN}}
        # Go to next entry if no pwdChangedTime
        if [ ! "${pwdChangedTime}" ]; then
                echo "${MY_LOG_HEADER} No password change date for ${login}. This account will never expire."
                pwdMaxAge=`$(get_policy_attribute ${pwdPolicySubentry} pwdMaxAge) | grep -w "pwdMaxAge:" | cut -d : -f 2 | sed "s/^ *//;s/ *$//"`
                echo "${login} : ${pwdMaxAge}"
                # What if password policy is not set
                pwdMaxAge=${pwdMaxAge:=1}
                if [ ${pwdMaxAge} -ne 0  ]; then
                        nb_never_expire_users=`expr ${nb_never_expire_users} + 1`
                        PWD_NO_EXPIRY_USERS="${PWD_NO_EXPIRY_USERS}, ${login} <${mail}>"
                fi
                continue
        fi

        # Go to next entry if no pwdPolicySubEntry and no default policy
        if [ ! "${pwdPolicySubentry}" -a ! "${MY_LDAP_DEFAULTPWDPOLICYDN}" ]; then
                echo "${MY_LOG_HEADER} No password policy for ${login}"
                continue
        fi

        pwdMaxAge=`$(get_policy_attribute ${pwdPolicySubentry} pwdMaxAge) | grep -w "pwdMaxAge:" | cut -d : -f 2 \
                | sed "s/^ *//;s/ *$//"`
        pwdExpireWarning=`$(get_policy_attribute ${pwdPolicySubentry} pwdExpireWarning) | grep -w "pwdExpireWarning:" | cut -d : -f 2 \
                | sed "s/^ *//;s/ *$//"`

        # Replace MAIL_DELAY by pwdExpireWarning if exists
        MY_MAIL_DELAY=${MY_MAIL_DELAY:=$pwdExpireWarning}

        # Retrieves time difference between today and last change.
        if [ "${pwdChangedTime}" ]; then
                s=`echo ${pwdChangedTime} | cut -c 13-14`
                m=`echo ${pwdChangedTime} | cut -c 11-12`
                h=`echo ${pwdChangedTime} | cut -c 9-10`
                d=`echo ${pwdChangedTime} | cut -c 7-8`
                M=`echo ${pwdChangedTime} | cut -c 5-6`
                y=`echo ${pwdChangedTime} | cut -c 1-4`
                currentTime=`getTimeInSeconds`
                pwdChangedTime=`getTimeInSeconds "$y $M $d $h $m $s"`
                diffTime=`expr ${currentTime} - ${pwdChangedTime}`
        fi

        # Go to next user if password already expired
        expireTime=`expr ${pwdChangedTime} + ${pwdMaxAge}`
        if [ ${currentTime} -gt ${expireTime} ]; then
                nb_expired_users=`expr ${nb_expired_users} + 1`
                echo "${MY_LOG_HEADER} Password expired for ${login}"
                PWD_EXPIRED_USERS="${PWD_EXPIRED_USERS}, ${login} <${mail}>"
                continue
        fi

        # ALL LDAP attributes should be there, else continue to next user
        if [ "${mail}" -a "${name}" \
                -a "${login}" -a "${diffTime}" -a "${pwdMaxAge}" ]
        then
                # Ajusts time with delay
                diffTime=`expr ${diffTime} + ${MY_MAIL_DELAY}`
                if [ ${diffTime} -gt ${pwdMaxAge} ]; then
                        logmsg="${MY_MAIL_BODY}"
                        logmsg=`echo ${logmsg} | sed "s/%name/${name}/; \
                                s/%login/${login}/"`

                        # Sending mail...

                        echo "${logmsg}" | ${MY_MAIL_BIN} -s "${MY_MAIL_SUBJECT}" ${mail}

                        # Print debug information on STDERR
                        echo "${MY_LOG_HEADER} Mail sent to user ${login} (${mail})"

                        # Increment warning counter
                        nb_warning_users=`expr ${nb_warning_users} + 1`
                        PWD_WARN_USERS="${PWD_WARN_USERS}, ${login} <${mail}>"
                fi
        fi

done < ${result_file}

PWD_NO_EXPIRY_USERS=${PWD_NO_EXPIRY_USERS#","}
PWD_EXPIRED_USERS=${PWD_EXPIRED_USERS#","}
PWD_WARN_USERS=${PWD_WARN_USERS#","}
HIPCHAT_NOTIFICATION_COLOR=green

NOTIFY_ADMIN_MSG=""
NOTIFY_ADMIN_MSG="${NOTIFY_ADMIN_MSG}\tTotal number of Users checked: ${nb_users} \n"
NOTIFY_ADMIN_MSG="${NOTIFY_ADMIN_MSG}\tAccounts expired: ${nb_expired_users} \n"
[[ ${nb_expired_users} -ne 0  ]] && \
        { NOTIFY_ADMIN_MSG="$NOTIFY_ADMIN_MSG\t\tList : $PWD_EXPIRED_USERS (sadpanda)\n"; HIPCHAT_NOTIFICATION_COLOR=red ;}
NOTIFY_ADMIN_MSG="${NOTIFY_ADMIN_MSG}\tAccounts set to never expire: ${nb_never_expire_users} \n"
[[ ${nb_never_expire_users} -ne 0  ]] && \
        { NOTIFY_ADMIN_MSG="$NOTIFY_ADMIN_MSG\t\t List : $PWD_NO_EXPIRY_USERS (doh)\n"; HIPCHAT_NOTIFICATION_COLOR=red ;}
NOTIFY_ADMIN_MSG="${NOTIFY_ADMIN_MSG}\tAccounts in warning for expiry: ${nb_warning_users} \n"
[[ ${nb_warning_users} -ne 0  ]] && \
        { NOTIFY_ADMIN_MSG="$NOTIFY_ADMIN_MSG\t\tList : $PWD_WARN_USERS (notbad)\n"; HIPCHAT_NOTIFICATION_COLOR=yellow ;}

echo -e "${NOTIFY_ADMIN_MSG}"

case ${NOTIFIER} in
        "mail")
            if [ ! "${MY_MAINTAINER_EMAIL_ADDRESS}" ]; then
                        echo "Maintainer email address is missing. Can't send emails."
                        exit 1
                else
                        echo "${NOTIFY_ADMIN_MSG}" | ${MY_MAIL_BIN} -s "${MY_MAIL_SUBJECT}" ${mail}
        fi
          ;;
        "hipchat")
                if [ ! "${HIPCHAT_SERVER_URL}" -a ! "${HIPCHAT_ROOM_ID}" -a ! "HIPCHAT_ROOM_TOKEN" ]; then
                        echo "Hipchat required parameters are missing. Hipchat server url, room id and integration token is required."
                        exit 1
                else
                        curl -H "Content-Type: application/json" \
                        -X POST \
                        -d "{\"color\": \"${HIPCHAT_NOTIFICATION_COLOR}\",\"from\":\"LDAP Account Notification\", \"message_format\": \"text\", \"message\": \"${NOTIFY_ADMIN_MSG}\"}" \
                        "${HIPCHAT_SERVER_URL}/v2/room/${HIPCHAT_ROOM_ID}/notification?auth_token=${HIPCHAT_ROOM_TOKEN}"
        fi
          ;;
        *)
          echo "Notifier (${NOTIFIER}) is not supported. Only hipchat and mail notifier."
          exit 1
          ;;
esac


# Delete temporary files
rm -rf ${tmp_dir}

# Exit
exit 0