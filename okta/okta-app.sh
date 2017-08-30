#!/bin/bash

curl="curl --silent  -H 'accept: application/json' -H 'cache-control: no-cache' -H 'content-type: application/json'"

base_url=""
api_key=""
app_name=""
sso_url=""

username='${source.email}'
subjectNameIdFormat='${user.userName}'
idpIssuer='${org.externalKey}'

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

usage()
{
cat << EOF
usage: $0 [options] command

This script creates/delete Okta application

OPTIONS:
   -h      Show this message
   -b      Url of Okta account
   -k      Okta API key
   -a      Okta application name
   -u      Url of user application to use for callback

Example:
Create application:
$0 -b 'https://example.okta.com' -k aBCdEf0GhiJkLMno1pq2 -a 'My okta app'  -u 'https://example.net/your_application/callback' create
Delete application:
$0 -id 'https://example.okta.com' -k aBCdEf0GhiJkLMno1pq2 -a 'My okta app'  -u 'https://example.net/your_application/callback' delete
EOF
}

while getopts ":b:k:a:u:c" OPTION
do
    case $OPTION in
    b)
        base_url="$OPTARG"
    ;;
    k)
        api_key="$OPTARG"
    ;;
    a)
        app_name="$OPTARG"
    ;;
    u)
        sso_url="$OPTARG"
    ;;
    c)
        operation="$OPTARG"
    ;;
    h)
        usage
        exit 1
    ;;
    \?)
        usage
        exit 1
    ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
    ;;
    esac
done

cat << EOF > "${DIR}/app.json"
{
  "label": "${app_name}",
  "accessibility": {
    "selfService": false,
    "errorRedirectUrl": null,
    "loginRedirectUrl": null
  },
  "visibility": {
    "autoSubmitToolbar": false,
    "hide": {
      "iOS": false,
      "web": false
    }
  },
  "features": [],
  "signOnMode": "SAML_2_0",
  "credentials": {
    "userNameTemplate": {
      "template": "$username",
      "type": "BUILT_IN"
    },
    "signing": {}
  },
  "settings": {
    "app": {},
    "notifications": {
      "vpn": {
        "network": {
          "connection": "DISABLED"
        },
        "message": null,
        "helpUrl": null
      }
    },
    "signOn": {
      "defaultRelayState": "",
      "ssoAcsUrl": "${sso_url}",
      "idpIssuer": "http://www.okta.com/$idpIssuer",
      "audience": "${sso_url}",
      "recipient": "${sso_url}",
      "destination": "${sso_url}",
      "subjectNameIdTemplate": "$subjectNameIdFormat",
      "subjectNameIdFormat": "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress",
      "responseSigned": true,
      "assertionSigned": true,
      "signatureAlgorithm": "RSA_SHA256",
      "digestAlgorithm": "SHA256",
      "honorForceAuthn": true,
      "authnContextClassRef": "urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport",
      "spIssuer": null,
      "requestCompressed": false,
      "attributeStatements": []
    }
  }
}
EOF


function check {
    searched_app=$1
    found_app=$($curl -G -H "authorization: SSWS $api_key" "$base_url/api/v1/apps" --data-urlencode "q=$app_name" | jq -r .[0].label)
    if [ "$searched_app" = "$found_app" ]; then
        return 0
    else
        return 1
    fi
}

function print_creds {
    fileOption="$1"
    metadataFile="${fileOption:=creds.xml}"
    idpIssuerId=$(xpath "${metadataFile}" "/*[local-name()='EntityDescriptor']/@entityID" 2>/dev/null | awk -F'"' '$0=$2')
    idpSsoUrl=$(xpath "${metadataFile}" "/*[local-name()='EntityDescriptor']/*[local-name()='IDPSSODescriptor']/*[local-name()='SingleSignOnService' and @Binding='urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST']/@Location" 2>/dev/null |awk -F'"' '$0=$2')
    xpath "${metadataFile}" "/*[local-name()='EntityDescriptor']/*[local-name()='IDPSSODescriptor']/*[local-name()='KeyDescriptor' and @use='signing']/*[local-name()='KeyInfo']/*[local-name()='X509Data']/*[local-name()='X509Certificate']/text()" 2>/dev/null | tr " " "\n" | sed '1s/^/-----BEGIN CERTIFICATE-----\'$'\n/g' | sed '$s/$/\'$'\n-----END CERTIFICATE-----/g' > okta.pem
    if [ -s okta.pem ]; then
          openssl base64 -in okta.pem -out okta.base64
          cat <<EOF
SAML Protocol Configuration:
OktaIssuerId=${idpIssuerId}
OktaSSOUrl=${idpSsoUrl}
OktaBase64Cert=$(tr -d '\r\n' < okta.base64)
EOF
    else
      echo "Okta certificate is empty, maybe application was deactivated."
      return 1
    fi
}

function create {
    $curl -s -X POST "$base_url/api/v1/apps" -H "authorization: SSWS $api_key" -H 'accept: application/json' -H 'cache-control: no-cache' -H 'content-type: application/json' --data-binary "@$DIR/app.json" > /dev/null
    if check "$app_name"; then
        echo "Okta application $app_name was created"
        return 0
    else
        echo "Okta application $app_name was not found"
        return 1
    fi
}

function get_creds {
    app_info=$($curl -G -H "authorization: SSWS $api_key" "$base_url/api/v1/apps" --data-urlencode "q=$app_name")
    app_id=$(echo "$app_info" | jq -r .[0].id)
    app_kid=$(echo "$app_info" | jq -r .[0].credentials.signing.kid)
    app_creds=$(curl -s "$base_url/api/v1/apps/$app_id/sso/saml/metadata?kid=$app_kid" -H "authorization: SSWS $api_key" -H 'cache-control: no-cache' -H 'content-type: application/json' -H 'accept: application/xml')
    echo "$app_creds" > "${DIR}/creds.xml"
    if print_creds "${DIR}/creds.xml"; then
      return 0
    else
      return 1
    fi
}

if check "$app_name"; then
  echo "Okta application with name \"$app_name\" already exists."
  echo "Getting \"$app_name\" configuration..."
  get_creds
  exit 0
fi
if create; then
  get_creds
fi



