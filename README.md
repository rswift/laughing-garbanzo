### Intro
A very quick and dirty exploration of the new AWS IAM Roles Anywhere feature...

Cobbled this together from a few sources:
* https://openssl-ca.readthedocs.io/en/latest/introduction.html
* https://www.openssl.org/docs/manmaster/man5/x509v3_config.html
* `man openssl`
* https://docs.aws.amazon.com/rolesanywhere/latest/userguide/credential-helper.html

### Usage
The [create.sh](./create.sh) script endeavours to create the root & intermediate certificate authorities, then create and sign (with the intermediate) a user cert... With those artefacts, it relies on you having appropraite AWS permissions to create the Trust Anchor, a Role (using the AWS read only policy) and a Profile.

The [set-creds.sh](./set-creds.sh) script must be run as `. ./set-creds.sh` in order to set the AWS environment variables. Otherwise, they'll set themselves inside the script, then be lost when the script ends. If it works, then you'll have the permission scope of the role that is linked to the profile, authenticated via the certs. Magic.

### Some maybe useful links
* https://docs.aws.amazon.com/rolesanywhere/latest/userguide/trust-model.html
* https://docs.aws.amazon.com/rolesanywhere/latest/userguide/monitoring-subjects.html
* https://docs.aws.amazon.com/awscloudtrail/latest/userguide/view-cloudtrail-events.html
* https://docs.aws.amazon.com/IAM/latest/UserGuide/cloudtrail-integration.html#cloudtrail-integration_signin-tempcreds
* https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_identifiers.html

### Refunds
Absolutely no warranty provided, this worked fine on my Mac this evening (macOS 12.5, homebrew up-to-date etc.) so any issues, please scratch your noggin and figure it out 🖖

### Refinement
You'll absolutely want to [delve into the finer detail](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/trust-model.html#trust-policy "AWS IAM Roles Anywhere Trust Model docs"), such as using the `aws:PrincipalTag/x509Subject/[CN|OU|O]` condition! Tweak [create.sh](./create.sh) to bring in an edited (for your `CN`/`OU`, or whatever you wish to explore) version of [rolesanywhere-role-trust-with-condition.json](./rolesanywhere-role-trust-with-condition.json).

To determine the unique details of the principal, using a CloudTrail event for the `rolesanywhere:CreateSession` API call as an example, if that the JSON for that API call is in a file called `createsession.json`, the Accedd Key Id and Username can be extracted with `jq`:

```sh
$ export IAM_ROLES_ANYWHERE_SUBJECT_USERNAME=$(cat createsession.json | jq -r '.responseElements.credentialSet[].assumedRoleUser.arn' | cut -d\/ -f3)
echo ${IAM_ROLES_ANYWHERE_SUBJECT_USERNAME}
57c882199301ba90e853e3f2b666976dverydeadbeef13de5ea956d3eb932e12eb
$ export IAM_ROLES_ANYWHERE_SUBJECT_ACCESS_KEY_ID=$(cat createsession.json | jq -r '.responseElements.credentialSet[].credentials.accessKeyId')
echo ${IAM_ROLES_ANYWHERE_SUBJECT_ACCESS_KEY_ID}
ASIAZ5B2X3U2EQ5G3ZCC
```

then obviously that can be plugged in elsewhere:
```sh
$ aws cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=${IAM_ROLES_ANYWHERE_SUBJECT_USERNAME}
{
    "Events": [
        {
            "EventId": "19091764-dead-beef-cafe-2faa58d8864e",
            "EventName": "GetCallerIdentity",
            "ReadOnly": "true",
            "AccessKeyId": "ASIAZ5B2X3U2EQ5G3ZCC",
            "EventTime": "2022-07-29T12:30:43+01:00",
            "EventSource": "sts.amazonaws.com",
            "Username": "57c882199301ba90e853e3f2b666976dverydeadbeef13de5ea956d3eb932e12eb",
            "Resources": [],
            "CloudTrailEvent": "{\"eventVersion\":\"1.08\",\"userIdentity\":{
            ...
        }
    ],
    "NextToken": "eyJOZXh0VG9rZW4iOiBuddXsabciYm90b190cnVuY2F0ZV9hbW21bnQi0iAxfQ=="
}
```

Having said that, hope this is useful to someone out there...

### Pretty Pictures...
Oh, and the missing diagram, every repo needs a diagram:

![IAM Roles Anywhere](./IAMRolesAnywhere.png)