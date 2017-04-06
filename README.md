# Supported tags and respective Dockerfile links

- [`0.1.0`, `0.1.0` (*0.1.0/Dockerfile*)](https://github.com/Accenture/adop-ldap-notifier/blob/master/Dockerfile.md)

# What is adop-ldap-notifier?

adop-ldap-notifer is a docker image for notifying the users if the password for ldap user has expired or will be expired. Notifier will only work if ppolicy module is loaded with your LDAP installation. It allows you to send the notification through email or hipchat.

When using email notification, this image sends out the expiry warning to the users as well as the maintainer using the script running in cron every day and the email address for user is derived from the mail attribute in ldap. Maintainer's email address has to be provided.

Alternatively you can use hipchat notification and it requires a hipchat server along with a room to which hipchat notifier has got access to send notification to. Notifer gets the access through the token for a particular hipchat.


## Build this image

`docker build -t adop-ltb-notifier .`

## How to use this image

The easiest way to run adop-ldap-notifier image is as follow:
```
docker run --name <your-container-name> -e LDAP_SERVER="ldap://ldap:389"  -e LDAP_USERNAME="<ldap root dn>"  -e LDAP_EXPIRY_NOTIFIER="mail" -e SLAPD_DEFAULT_POLICY="c<default policy dn>" -e LDAP_USER_BASE_DN="<people dn>" -e MAINTAINER_MAIL_ADDRESS="<your email address>" -d accenture/adop-ldap-notifier:VERSION
```

Runtime configuration can be provided using environment variables:

* `LDAP_EXPIRY_NOTIFIER`, This attribute controls how you want to get notified. Allowed values 'mail' and 'hipchat'
* `MAINTAINER_MAIL_ADDRESS`, Email address of the maintainer. mandatory attribute when 'mail' notifier is choosen.
* `LDAP_SERVER`, the LDAP SERVER URL. Defaults to 'ldap://localhost:389'.
* `LDAP_PASSWORD`, the LDAP admin password. This is mandatory attribute.
* `LDAP_USER_BASE_DN`, the base dn for users. This is mandatory attribute.
* `SLAPD_DEFAULT_POLICY`, the default password policy for ldap users. This is mandatory attribute.
* `HIPCHAT_SERVER_URL`, Hipchat server url. This is mandatory attribute for 'hipchat' notifier.
* `HIPCHAT_ROOM_TOKEN`, Hipchat room token. This is mandatory attribute for 'hipchat' notifier. 
* `HIPCHAT_ROOM_ID`, Hipchat room id. This is mandatory attribute for 'hipchat' notifier. 


# License
Please view [licence information](LICENCE.md) for the software contained on this image.

#Supported Docker versions

This image is officially supported on Docker version 1.9.1.
Support for older versions (down to 1.6) is provided on a best-effort basis.

# User feedback

## Issues
If you have any problems with or questions about this image, please contact us through a [GitHub issue](https://github.com/Accenture/adop-ldap-notifier/issues).

## Contribute
You are invited to contribute new features, fixes, or updates, large or small; we are always thrilled to receive pull requests, and do our best to process them as fast as we can.

Before you start to code, we recommend discussing your plans through a [GitHub issue](https://github.com/Accenture/adop-ldap-notifier/issues), especially for more ambitious contributions. This gives other contributors a chance to point you in the right direction, give you feedback on your design, and help you find out if someone else is working on the same thing.

