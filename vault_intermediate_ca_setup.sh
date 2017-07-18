#!/bin/bash -e

# Setup a Root CA in vault
# Generate and sign an Intermediate cert
#
# Requires:
# * A running vault server already initialzed and unsealed
# * Environment variable VAULT_TOKEN is set
# * vault cli (https://www.vaultproject.io)
# * httpie (https://github.com/jkbrzt/httpie)
# * jq (https://stedolan.github.io/jq/)
#
# Note: we use httpie + jq because vault write commands aren't able to return
# formatted json for parsing

set -e

VAULT_ADDR=${VAULT_ADDR:-http://127.0.0.1:8200}

ROOT_PATH=${ROOT_PATH:-root_ca}
INTR_PATH=${INTR_PATH:-intermediate_acme_com}

COMPANY="${COMPANY:-Acme Inc.}"
DOMAIN="${DOMAIN:-acme.com}"
UNDER_DOM=${DOMAIN//\./_}

# check dependencies
hash vault 2> /dev/null || { echo "Please install vault (https://www.vaultproject.io)"; exit 1; }
hash http 2> /dev/null || { echo "Please install httpie (https://github.com/jkbrzt/httpie)"; exit 1; }
hash jq 2> /dev/null || { echo "Please install jq (https://stedolan.github.io/jq/)"; exit 1; }

[[ "${VAULT_TOKEN}" == "" ]] && { echo "VAULT_TOKEN is not set"; exit 1; }

# Mount a PKI backend for the root Certificate authority
echo "Creating root CA"
vault mount -path="${ROOT_PATH}" pki

# Set the max TTL for the root CA to 10 years
echo "Tuning root CA"
vault mount-tune -max-lease-ttl="87600h" "${ROOT_PATH}"

# Generate the root CA keypair, the key is stored internally to vault
echo "Generating root CA cert"
vault write ${ROOT_PATH}/root/generate/internal common_name="${COMPANY} Root CA" ttl="87600h"
# TODO: setup CRL and OCSP urls

# Mount the intermediate CA for the zone
echo "Creating intermediate CA"
vault mount -path=${INTR_PATH} pki

# Set the max TTL for ${DOMAIN} certs to 1 year
echo "Tuning intermediate CA"
vault mount-tune -max-lease-ttl=8760h ${INTR_PATH}

# Generate CSR for ${DOMAIN} to be signed by the root CA, the key is stored
# internally to vault
echo "Generating intermediate CSR"
http POST ${VAULT_ADDR}/v1/${INTR_PATH}/intermediate/generate/internal X-Vault-Token:$VAULT_TOKEN common_name=${DOMAIN} | jq -r .data.csr > ${UNDER_DOM}.csr

# Generate and sign the ${DOMAIN} certificate as an intermediate CA
echo "Get intermediate cert"
http POST ${VAULT_ADDR}/v1/${ROOT_PATH}/root/sign-intermediate X-Vault-Token:$VAULT_TOKEN ttl="8760h" csr=@${UNDER_DOM}.csr | jq -r .data.certificate > ${UNDER_DOM}.crt

# Add signed ${DOMAIN} certificate to intermediate CA backend
echo "Add intermediate cert"
vault write ${INTR_PATH}/intermediate/set-signed certificate=@${UNDER_DOM}.crt

# Create role for issuing ${DOMAIN} certificates
# Max least time is 14 days
echo "Create a role for subdomain certs"
vault write ${INTR_PATH}/roles/${UNDER_DOM} allowed_domains="${DOMAIN}" lease_max="336h" allow_subdomains=true

# Issue a cert for an ${DOMAIN} subdomain valid for 1 week
echo "Issue a subdomain cert"
http POST ${VAULT_ADDR}/v1/${INTR_PATH}/issue/${UNDER_DOM} X-Vault-Token:$VAULT_TOKEN common_name="foo.${DOMAIN}" ttl="168h" | jq -r .data.private_key,.data.certificate,.data.issuing_ca > foo_${UNDER_DOM}.crt

echo "Intermediate CA cert:"
openssl x509 -in ${UNDER_DOM}.crt -noout -subject -issuer

echo "Subdomain Cert:"
openssl x509 -in foo_${UNDER_DOM}.crt -noout -subject -issuer
