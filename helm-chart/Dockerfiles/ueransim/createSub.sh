#!/usr/bin/env bash
numSubs="$1"
imsi=208930000000000
IP=172.18.0.4
PORT=32539
username=admin
password=1423

ContentTypeHeader="Content-Type: application/json"
CookieHeader="Cookie: connect.sid=s%3AuoN9LIawCzzhpqAEGcA1-w0rs9TXz-8m.7aDO%2F8zQSzieLJR%2BE9c0g%2BAA4z9AijdAbW8ZftIvgu8"
AuthHeader="Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjp7Il9pZCI6IjYwYjU4MDg1YjM2N2FjMDAxOThjMzg3YiIsInVzZXJuYW1lIjoiYWRtaW4iLCJyb2xlcyI6WyJhZG1pbiJdfSwiaWF0IjoxNjIyNTA4Nzg2fQ.4tNgvkinGqqYfkGe-371tnZwwvAhQGlmxvIE6cUw2hQ"
XCSRFTOKENHeader="X-CSRF-TOKEN: eBjhr7PLxbgnAHJJ4YcmCU2WxxY1tYBPo399U="
URI="http://$IP:$PORT/api/db/Subscriber"

jsonStr='{"imsi":"208930000000027","security":{"k":"465B5CE8 B199B49F AA5F0A2E E238A6BC","amf":"8000","op_type":0,"op_value":"E8ED289D EBA952E4 283B54E8 8E6183CA","op":null,"opc":"E8ED289D EBA952E4 283B54E8 8E6183CA"},"ambr":{"downlink":{"value":1,"unit":3},"uplink":{"value":1,"unit":3}},"slice":[{"sst":1,"default_indicator":true,"session":[{"name":"internet","type":3,"pcc_rule":[],"ambr":{"uplink":{"value":1,"unit":3},"downlink":{"value":1,"unit":3}},"qos":{"index":9,"arp":{"priority_level":8,"pre_emption_capability":1,"pre_emption_vulnerability":1}}}]}],"schema_version":1}'

run_loop () {
  for i in $(seq 1 $numSubs);
  do
    imsi=$((imsi+1))
    variable="$imsi"
    jsonData="$(jq --arg variable "$variable" '.imsi = $variable' <<<$jsonStr)"
    status_code=$(curl --write-out '%{http_code}\n' --silent --output /dev/null -u $username:$password -H "$ContentTypeHeader" -H "$CookieHeader"  -H "$AuthHeader" -H "$XCSRFTOKENHeader" --request POST --data "$jsonData" $URI)
    if [[ "$status_code" -ne 201 ]] ; then
      echo "Failed to create subscriber #$i with imsi $imsi"
    else
      echo "Created subscriber #$i with imsi $imsi"
    fi
  done
}

run_loop
