#!/bin/zsh

#
# Retrieve short lived creds from AWS IAM Roles Anywhere, this script is a proof-of-concept, not sure this is production ready ¯\_(ツ)_/¯
#
# Using defaults in the variables means they can be overridden by simply setting them on execution, to :
#
#  RA_REGION=us-east-1 RA_ROLE_NAME=WibbleWobble . ./set-creds.sh
#
# To generate a .aws directory with a config and credentials file (for Docker volume mapping) add --create-aws-files
#
# See also:
#  https://stedolan.github.io/jq/
#  https://docs.aws.amazon.com/rolesanywhere/latest/userguide/credential-helper.html
#  https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html
#

#
# Chapeau https://stackoverflow.com/a/1683850/259122 for the white space trimming! 🤓
#
CMD=$(echo `ps -ef | grep $$ | grep ${PPID} | head -1 | awk '{$1=$2=$3=$4=$5=$6=$7=$8=""; print $0}'`)
CMD="${CMD## }"
CMD="${CMD%% }"
if [ "$0" = "${CMD}" ]; then
  echo "Are you sure you ran this as \". $0\"? If you didn't run it that way, the AWS variables won't persist after this script has run, so no AWS action for you! 😕"
fi

RA_USER_CERT=${RA_USER_CERT:-user.cert.pem}
RA_PRIVATE_KEY=${RA_PRIVATE_KEY:-user.key.pem}

RA_REGION=${RA_REGION:-eu-west-2}
RA_ACCOUNT_ID=${RA_ACCOUNT_ID:-123456789012}

RA_PROFILE_ID=${RA_PROFILE_ID:-86e59d9c-dead-cafe-beef-54c63717fd8a}
RA_TRUST_ANCHOR_ID=${RA_TRUST_ANCHOR_ID:-f80b6d6d-dead-cafe-beef-6de6e2c1f4b2}
RA_ROLE_NAME=${RA_ROLE_NAME:-RolesAnywhereExploring}

#
# With AWS creds that permit use of the rolesanywhere API, something like (the trust anchor and profile names match the creation script elsewhere in this repo, tweak as per...):
#
# aws rolesanywhere list-profiles --query "profiles[?name=='Read Only'].profileId" --output text --no-cli-pager
# aws rolesanywhere list-trust-anchors --query "trustAnchors[?name=='Intermediate CA Trust'].trustAnchorId" --output text --no-cli-pager
#
# The full ARN would make most sense to retrieve, but I'm trying to expand detail in the script, hence the use of ID instead
#
RA_PROFILE_ARN=arn:aws:rolesanywhere:${RA_REGION}:${RA_ACCOUNT_ID}:profile/${RA_PROFILE_ID}
RA_TRUST_ANCHOR_ARN=arn:aws:rolesanywhere:${RA_REGION}:${RA_ACCOUNT_ID}:trust-anchor/${RA_TRUST_ANCHOR_ID}
RA_ROLE_ARN=arn:aws:iam::${RA_ACCOUNT_ID}:role/${RA_ROLE_NAME}

which aws_signing_helper > /dev/null
RC=$?
if [ ${RC} -ne 0 ]; then
  echo "aws_signing_helper utility doesn't appear on the path, this means IAM Roles Anywhere short lived creds cannot be retrieved by this script 🙁"
else
  RA_CREDS=$(aws_signing_helper credential-process --certificate ${RA_USER_CERT} --private-key ${RA_PRIVATE_KEY} --profile-arn ${RA_PROFILE_ARN} --role-arn ${RA_ROLE_ARN} --trust-anchor-arn ${RA_TRUST_ANCHOR_ARN} --region ${RA_REGION})
  RC=$?
  if [ ${RC} -ne 0 ]; then
    echo "Failed to retrieve short lived credentials via IAM Roles Anywhere: ${RC}"
  else
    which jq > /dev/null
    if [ $? -eq 0 ]; then
      export AWS_ACCESS_KEY_ID=$(echo ${RA_CREDS} | jq -r .AccessKeyId)
      export AWS_SECRET_ACCESS_KEY=$(echo ${RA_CREDS} | jq -r .SecretAccessKey)
      export AWS_SESSION_TOKEN=$(echo ${RA_CREDS} | jq -r .SessionToken)
      export AWS_REGION=${RA_REGION}
      unset AWS_PROFILE

      STS_IDENTITY=$(aws sts get-caller-identity --no-cli-pager)
      if [ $? -eq 0 ]; then
        STS_EXPIRY=$(echo ${RA_CREDS} | jq -r .Expiration)
        UNIX_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "${STS_EXPIRY}" +"%s")
        LOCAL_TIME=$(date -r ${UNIX_EPOCH})
        (( EXPIRY_MINUTES  = ($UNIX_EPOCH - `date +"%s"`) / 60 ))
        (( EXPIRY_SECONDS  = ($UNIX_EPOCH - `date +"%s"`) % 60 ))
        if [ ${EXPIRY_SECONDS} -gt 60 ]; then
          (( EXPIRY_MINUTES  = ${EXPIRY_MINUTES} + 1 ))
          EXPIRY_IN="just under ${EXPIRY_MINUTES} minutes"
        else
          # because i'm a fussy twat...
          MIN_S="s"
          if [ ${EXPIRY_MINUTES} -eq 1 ]; then
            MIN_S=""
          fi
          SEC_S="s"
          if [ ${EXPIRY_SECONDS} -eq 1 ]; then
            SEC_S=""
          fi
          EXPIRY_IN="${EXPIRY_MINUTES} minute${MIN_S} ${EXPIRY_SECONDS} second${SEC_S}"
        fi
        echo "Successfully established as an AWS IAM principal 👌\n"
        echo "The credentials are valid for ${EXPIRY_IN}, or until ${LOCAL_TIME}, or ${UNIX_EPOCH} for those who count the seconds from 1970-01-01T00:00:00Z 🕰\n"
        echo "To clear them, use:\n unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN\n"
        PRINCIPAL_ID=$(echo ${STS_IDENTITY} | jq -r .UserId)
        SUBJECT_USERNAME=$(echo ${PRINCIPAL_ID} | cut -d: -f2)
        X509_CN=$(openssl x509 -noout -in user.cert.pem -subject -nameopt sep_multiline | grep 'CN=' | awk '{print $1}')
        echo "CloudTrail Username: ${SUBJECT_USERNAME}"
        echo " ↪︎ aws cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=${SUBJECT_USERNAME} --region ${RA_REGION}"
        echo " ↪︎ https://${RA_REGION}.console.aws.amazon.com/cloudtrail/home?region=${RA_REGION}#/events?Username=${SUBJECT_USERNAME}"
        echo "\nAWS access key: ${AWS_ACCESS_KEY_ID}"
        echo " ↪︎ aws cloudtrail lookup-events --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=${AWS_ACCESS_KEY_ID} --region ${RA_REGION}"
        echo " ↪︎ https://${RA_REGION}.console.aws.amazon.com/cloudtrail/home?region=${RA_REGION}#/events?AccessKeyId=${AWS_ACCESS_KEY_ID}"
        echo "\nCloudTrail Event entries for the subject will contain:"
        echo " ↪︎ userIdentity.principalId: ${PRINCIPAL_ID}"
        echo " ↪︎ userIdentity.arn: `echo ${STS_IDENTITY} | jq -r .Arn`"
        echo " ↪︎ userIdentity.sessionContext.sourceIdentity: ${X509_CN}"
        if [ "$1" = "--create-aws-files" ]; then
          rm -rf .aws; mkdir .aws
          TMP_CONFIG=.aws/config
          TMP_CREDS=.aws/credentials
          echo "[default]\nregion=${RA_REGION}\noutput=json" > ${TMP_CONFIG}
          echo "[default]" > ${TMP_CREDS}
          echo "aws_access_key_id=${AWS_ACCESS_KEY_ID}" >> ${TMP_CREDS}
          echo "aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}" >> ${TMP_CREDS}
          echo "aws_session_token=${AWS_SESSION_TOKEN}" >> ${TMP_CREDS}
          PWD=$(pwd | sed -e 's/ /\\ /g')
          echo "\nAWS config & credentials files created, for docker volumes, use something like \"-v ${PWD}/.aws:/.aws\""
        fi
      else
        echo "Failed to get the AWS identity from the IAM Roles Anywhere credentials 👎"
      fi
    else
      echo "Cannot find the jq utility, you'll need to manually set the AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY & AWS_SESSION_TOKEN environment variables from:\n\n${RA_CREDS}" 
    fi
  fi
fi