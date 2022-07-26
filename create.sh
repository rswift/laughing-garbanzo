#!/bin/zsh
#
# run this script from the repo root... please don't be too critical of its shortcomings, cobbled together sat on the sofa with my mac qone evening to scratch an itch 🖖
#

# so we can get back to where we started from nice and easily :)
pushd .

CA_BASE_CONFIG_FILE=openssl-root.conf
CA_BASE_DIR=$(grep '^dir' ${CA_BASE_CONFIG_FILE} | cut -d= -f2 | cut -c2-)
CA_CONFIG=${CA_BASE_DIR}/${CA_BASE_CONFIG_FILE}

INTERMEDIATE_BASE_CONFIG_FILE=openssl-intermediate.conf
INTERMEDIATE_BASE_DIR=$(grep '^dir' ${INTERMEDIATE_BASE_CONFIG_FILE} | cut -d= -f2 | cut -c2-)
INTERMEDIATE_CONFIG=${INTERMEDIATE_BASE_DIR}/${INTERMEDIATE_BASE_CONFIG_FILE}

mkdir -p ${CA_BASE_DIR}
cp ${CA_BASE_CONFIG_FILE} ${CA_BASE_DIR}

mkdir -p ${INTERMEDIATE_BASE_DIR}
cp ${INTERMEDIATE_BASE_CONFIG_FILE} ${INTERMEDIATE_BASE_DIR}

cd ${CA_BASE_DIR}
echo "\nUsing ${CA_BASE_DIR} for the Root CA directory, with the configuration file ${CA_BASE_CONFIG_FILE}\n"

#
# https://openssl-ca.readthedocs.io/en/latest/create-the-root-pair.html
#
mkdir certs crl newcerts
mkdir -m 700 private
touch index.txt
openssl rand -out serial -hex 32

echo "Creating a 4096 bit private key for the Root CA cert...\n"
openssl genrsa -aes256 -out private/ca.key.pem 4096
chmod 400 private/ca.key.pem

# 25 years, adjust to suit...
(( CA_EXPIRY_DAYS = 365 * 25 ))
echo "\nCreating the Root CA cert with an expiry in ${CA_EXPIRY_DAYS} days... (`date -v +${CA_EXPIRY_DAYS}d` 👈 ish)\n"
openssl req -config ${CA_CONFIG} -key private/ca.key.pem -new -x509 -days ${CA_EXPIRY_DAYS} -sha256 -extensions v3_ca -out certs/ca.cert.pem
chmod 444 certs/ca.cert.pem

echo "Created the Root CA cert (🤞), let's verify & display it...\n"
openssl x509 -noout -text -in certs/ca.cert.pem

#
# now for the intermediate...
#
echo "\nUsing ${INTERMEDIATE_BASE_DIR} for the Intermediate CA directory, with the configuration file ${INTERMEDIATE_BASE_CONFIG}\n"

#
# https://openssl-ca.readthedocs.io/en/latest/create-the-intermediate-pair.html
#
cd ${INTERMEDIATE_BASE_DIR}
mkdir certs crl csr newcerts
mkdir -m 700 private
touch index.txt
openssl rand -out serial -hex 32
cd ${CA_BASE_DIR}

echo "Creating a 4096 bit private key for the Intermediate CA cert...\n"
openssl genrsa -aes256 -out intermediate/private/intermediate.key.pem 4096
chmod 400 intermediate/private/intermediate.key.pem

echo "\nCreating a signing request for the Intermediate CA cert...\n"
openssl req -config ${INTERMEDIATE_CONFIG} -new -sha256 -key intermediate/private/intermediate.key.pem -out intermediate/csr/intermediate.csr.pem

# 10 years, adjust to suit...
(( INTERMEDIATE_EXPIRY_DAYS = 365 * 10 ))
INTERMEDIATE_SERIAL=$(cat serial)
echo "\nCreating the Intermediate CA, signed by the Root CA, with an expiry in ${INTERMEDIATE_EXPIRY_DAYS} days... (`date -v +${INTERMEDIATE_EXPIRY_DAYS}d` 👈 ish)\n"
openssl ca -config ${CA_CONFIG} -extensions v3_intermediate_ca -days ${INTERMEDIATE_EXPIRY_DAYS} -notext -md sha256 -in intermediate/csr/intermediate.csr.pem -out intermediate/certs/intermediate.cert.pem
chmod 444 intermediate/certs/intermediate.cert.pem

echo "\nCreated the Intermediate CA cert, signed by the Root CA (🤞), its serial number should be ${INTERMEDIATE_SERIAL}, let's verify & display it...\n"
openssl x509 -noout -text -in intermediate/certs/intermediate.cert.pem

echo "\nThe newly minted Intermediate should be valid when verified by the Root CA:"
openssl verify -CAfile certs/ca.cert.pem intermediate/certs/intermediate.cert.pem

CHAIN=intermediate/certs/ca-chain.cert.pem
echo "\nCreating the cert chain in ${CHAIN}..."
cat intermediate/certs/intermediate.cert.pem certs/ca.cert.pem > ${CHAIN}
chmod 444 ${CHAIN}

USER_CERT=user
USER_PRIVATE_KEY=intermediate/private/${USER_CERT}.key.pem
USER_CERT_FILE=intermediate/certs/${USER_CERT}.cert.pem
echo "\nCreating a 4096 bit user certificate (for ${USER}), signed by the Intermediate CA..."
openssl genrsa -out ${USER_PRIVATE_KEY} 4096
chmod 400 ${USER_PRIVATE_KEY}

echo "\nCreating a signing request for the ${USER_CERT} cert...\n"
openssl req -config ${INTERMEDIATE_CONFIG} -key ${USER_PRIVATE_KEY} -new -sha256 -out intermediate/csr/${USER_CERT}.csr.pem

USER_SERIAL=$(cat serial)
# 2 years, adjust to suit...
(( USER_EXPIRY_DAYS = 365 * 2 ))
echo "\nCreating the user cert, signed by the Intermediate CA, with an expiry in ${USER_EXPIRY_DAYS} days... (`date -v +${USER_EXPIRY_DAYS}d` 👈 ish)\n"
openssl ca -config ${INTERMEDIATE_CONFIG} -extensions usr_cert -days ${USER_EXPIRY_DAYS} -notext -md sha256 -in intermediate/csr/${USER_CERT}.csr.pem -out ${USER_CERT_FILE}
chmod 444 ${USER_CERT_FILE}

echo "\nCreated the Intermediate CA cert, signed by the Root CA (🤞), its serial number should be ${USER_SERIAL}, let's verify & display it...\n"
openssl x509 -noout -text -in ${USER_CERT_FILE}

echo "\nThe newly minted ${USER_CERT} cert, should be valid when verified by the Intermediate CA:"
openssl verify -CAfile ${CHAIN} ${USER_CERT_FILE}

echo "\nFor AWS IAM Roles Anywhere, the Trust Anchor requires the contents of ${CA_BASE_DIR}/${CHAIN}, then the cert from ${CA_BASE_DIR}/${USER_CERT_FILE} can be used to retrieve AWS short lived creds..."

#
# set the profile to whatever is needed - assumes you're familiar with the AWS config file, and that suitably equipped creds are available to this script... 🖖
#
export AWS_PROFILE=exploration
popd

#
# https://docs.aws.amazon.com/rolesanywhere/latest/userguide/getting-started.html#getting-started-step2
#
ROLE_NAME=RolesAnywhereExploring
POLICY=arn:aws:iam::aws:policy/ReadOnlyAccess
echo "Creating an IAM role (${ROLE_NAME}) with a rolesanywhere trust, attaching the policy: ${POLICY}"
ROLE_ARN=$(aws iam create-role --role-name ${ROLE_NAME} --assume-role-policy-document file://rolesanywhere-role-trust.json --no-cli-pager | grep '"Arn": ' | cut -d\" -f4)
aws iam attach-role-policy --role-name ${ROLE_NAME} --policy-arn ${POLICY}

echo "Creating the IAM Roles Anywhere Trust Anchor..."
TRUST_ANCHOR_ARN=$(aws rolesanywhere create-trust-anchor --enabled --name "Intermediate CA Trust" --source "sourceData={x509CertificateData=`cat ${CA_BASE_DIR}/${CHAIN}`},sourceType=CERTIFICATE_BUNDLE" --no-cli-pager --query trustAnchor.trustAnchorArn --output text)

echo "Creating the IAM Roles Anywhere Profile with a 15 minute session duration..."
ROLE_PROFILE_ARN=$(aws rolesanywhere create-profile --duration-seconds 900 --enabled --name "Read Only" --role-arns ${ROLE_ARN} --managed-policy-arns ${POLICY} --no-cli-pager --query profile.profileArn --output text)

echo "Created Trust Anchor and Profile, to use it, you need the aws_signing_helper (or some other mechanism) to send the ${USER_CERT_FILE} with parameters, in exchange for AWS short lived creds"
echo "See: https://docs.aws.amazon.com/rolesanywhere/latest/userguide/credential-helper.html"

CERT_FILE=${CA_BASE_DIR}/${USER_CERT_FILE}
PRIVATE_KEY=${CA_BASE_DIR}/${USER_PRIVATE_KEY}
echo "\nThe following syntax should probably work:\n\naws_signing_helper credential-process --certificate ${CERT_FILE} --private-key ${PRIVATE_KEY} --profile-arn ${ROLE_PROFILE_ARN} --role-arn ${ROLE_ARN} --trust-anchor-arn ${TRUST_ANCHOR_ARN}"
echo '\nThe aws_signing_helper command returns JSON that includes the AccessKeyId, SecretAccessKey & SessionToken needed to actually access AWS, jq would probably be your friend, something line:\n\nexport AWS_ACCESS_KEY_ID=$(echo ${ROLES_ANYWHERE_SIGNIN_RESPONSE} | jq -r .AccessKeyId)\nexport AWS_SECRET_ACCESS_KEY=$(echo ${ROLES_ANYWHERE_SIGNIN_RESPONSE} | jq -r .SecretAccessKey)\nexport AWS_SESSION_TOKEN=$(echo ${ROLES_ANYWHERE_SIGNIN_RESPONSE} | jq -r .SessionToken)'
echo "\nHaving set the shell variables (and unset AWS_PROFILE etc. if required), the \"aws sts get-caller-identity\" command can be used to return the principal details"

TMP_SCRIPT=/tmp/ra.$$.sh
echo "CREDS=\$(~/.bin/aws_signing_helper credential-process --certificate ${CERT_FILE} --private-key ${PRIVATE_KEY} --profile-arn ${ROLE_PROFILE_ARN} --role-arn ${ROLE_ARN} --trust-anchor-arn ${TRUST_ANCHOR_ARN})" > ${TMP_SCRIPT}
echo 'export AWS_ACCESS_KEY_ID=$(echo ${CREDS} | jq -r .AccessKeyId)' >> ${TMP_SCRIPT}
echo 'export AWS_SECRET_ACCESS_KEY=$(echo ${CREDS} | jq -r .SecretAccessKey)' >> ${TMP_SCRIPT}
echo 'export AWS_SESSION_TOKEN=$(echo ${CREDS} | jq -r .SessionToken)' >> ${TMP_SCRIPT}
echo 'unset AWS_PROFILE' >> ${TMP_SCRIPT}
echo 'aws sts get-caller-identity --no-cli-pager' >> ${TMP_SCRIPT}
echo 'aws rolesanywhere list-subjects --no-cli-pager' >> ${TMP_SCRIPT}
echo 'export TMP_USERID=$(aws sts get-caller-identity --query UserId --output text --no-cli-pager | cut -d: -f2)' >> ${TMP_SCRIPT}
echo 'sleep 120 && aws cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=${TMP_USERID}' >> ${TMP_SCRIPT}

echo "A script, that will probably need a tweak (path for the helper maybe) has been created here, might be interesting: ${TMP_SCRIPT}"