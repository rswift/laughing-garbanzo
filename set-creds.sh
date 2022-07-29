#!/bin/zsh

#
# this could be improved considerably if it checks for the presence of the requires jq & aws_signing_helper utilities etc. but hopefully is it a good starting point...
#
# https://stedolan.github.io/jq/
# https://docs.aws.amazon.com/rolesanywhere/latest/userguide/credential-helper.html
#

ps -ef | grep $$ | grep ${PPID} | grep -- '-zsh' > /dev/null || echo "Are you sure you ran this as \". $0\"? If you didn't run it that way, the AWS variables won't persist after this script has run, so no AWS action for you! 😕"

USER_CERT=user.cert.pem
PRIVATE_KEY=user.key.pem
PROFILE_ARN=arn:aws:rolesanywhere:[REGION]:[ACCOUNT ID]:profile/[PROFILE ID]
TRUST_ANCHOR_ARN=arn:aws:rolesanywhere:[REGION]:[ACCOUNT ID]:trust-anchor/[TRUST ANCHOR ID]
ROLE_ARN=arn:aws:iam::[ACCOUNT ID]:role/[ROLE NAME]

CREDS=$(~/.bin/aws_signing_helper credential-process --certificate ${USER_CERT} --private-key ${PRIVATE_KEY} --profile-arn ${PROFILE_ARN} --role-arn ${ROLE_ARN} --trust-anchor-arn ${TRUST_ANCHOR_ARN})
RC=$?
if [ ${RC} -ne 0 ]; then
  echo "Failed to retrieve short lived credentials via IAM Roles Anywhere: ${RC}"
  exit
fi

which jq || "Cannot find the jq utility, you'll need to manually set the AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY & AWS_SESSION_TOKEN environment variables from the 

export AWS_ACCESS_KEY_ID=$(echo ${CREDS} | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo ${CREDS} | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo ${CREDS} | jq -r .SessionToken)
unset AWS_PROFILE

aws sts get-caller-identity --no-cli-pager && echo "Successfully established as an AWS IAM principal 👌" || echo "Failed to get the AWS identity from the IAM Roles Anywhere credentials 👎"
