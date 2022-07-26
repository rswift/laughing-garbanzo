A very quick and dirty exploration of the new AWS IAM Roles Anywhere feature...

Cobbled this together from a few sources:
* https://openssl-ca.readthedocs.io/en/latest/introduction.html
* https://www.openssl.org/docs/manmaster/man5/x509v3_config.html
* https://docs.aws.amazon.com/rolesanywhere/latest/userguide/credential-helper.html

Absolutely no warranty provided, this worked fine on my Mac this evening (macOS 12.5, homebrew up-to-date etc.) so any issues, please scratch your noggin and figure it out 🖖

You'll absolutely want to delve into the finer detail, such as using the `aws:PrincipalTag/x509Subject/[CN|OU|O]` condition! 

Having said that, hope this is useful to someone out there...
