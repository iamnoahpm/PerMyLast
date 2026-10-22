#!/usr/bin/env bash
# Builds a THROWAWAY certificate chain shaped like Apple's (P-384 root and intermediate, P-256 leaf, Apple's marker
# extensions) so the App Store verification code can be tested without real Apple signatures.
# The keys here are test fixtures only and are worthless. Output: apple-test-chain.json
set -euo pipefail
cd "$(dirname "$0")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/ext.cnf" <<'CNF'
[req]
distinguished_name = dn
[dn]
[ca_ext]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign
[inter_ext]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign
1.2.840.113635.100.6.2.1 = ASN1:NULL
[leaf_ext]
basicConstraints = critical,CA:FALSE
1.2.840.113635.100.6.11.1 = ASN1:NULL
[leaf_plain]
basicConstraints = critical,CA:FALSE
CNF
gen() { # name curve
  openssl ecparam -name "$2" -genkey -noout -out "$tmp/$1.key"
}
gen root secp384r1; gen inter secp384r1; gen leaf prime256v1; gen rogue secp384r1
openssl req -x509 -new -key "$tmp/root.key" -sha384 -days 3650 -subj "/CN=Test Root CA - G3/O=Test" -extensions ca_ext -config "$tmp/ext.cnf" -out "$tmp/root.pem"
sign() { # name extsection parent-name subj days
  openssl req -new -key "$tmp/$1.key" -subj "$4" -config "$tmp/ext.cnf" -out "$tmp/$1.csr"
  openssl x509 -req -in "$tmp/$1.csr" -CA "$tmp/$3.pem" -CAkey "$tmp/$3.key" -CAcreateserial -sha384 -days "$5" -extfile "$tmp/ext.cnf" -extensions "$2" -out "$tmp/$1.pem" 2>/dev/null
}
sign inter inter_ext root "/CN=Test Intermediate/O=Test" 3000
sign leaf leaf_ext inter "/CN=Test Leaf/O=Test" 365
sign leafplain leaf_plain inter "/CN=Test Leaf Without Marker/O=Test" 365 2>/dev/null || { cp "$tmp/leaf.key" "$tmp/leafplain.key"; sign leafplain leaf_plain inter "/CN=Test Leaf Without Marker/O=Test" 365; }
openssl req -x509 -new -key "$tmp/rogue.key" -sha384 -days 3650 -subj "/CN=Rogue Root/O=Test" -extensions ca_ext -config "$tmp/ext.cnf" -out "$tmp/rogue.pem"
openssl req -new -key "$tmp/leaf.key" -subj "/CN=Expired Leaf/O=Test" -config "$tmp/ext.cnf" -out "$tmp/expired.csr"
openssl x509 -req -in "$tmp/expired.csr" -CA "$tmp/inter.pem" -CAkey "$tmp/inter.key" -CAcreateserial -sha384 -days 1 -extfile "$tmp/ext.cnf" -extensions leaf_ext -out "$tmp/expired.pem" 2>/dev/null

der() { openssl x509 -in "$tmp/$1.pem" -outform der | base64 | tr -d '\n'; }
fp() { openssl x509 -in "$tmp/$1.pem" -outform der | openssl dgst -sha256 | awk '{print $NF}'; }
key() { openssl pkcs8 -topk8 -nocrypt -in "$tmp/$1.key" -outform der | base64 | tr -d '\n'; }
cat > apple-test-chain.json <<JSON
{
  "root": "$(der root)", "rootSha256": "$(fp root)",
  "intermediate": "$(der inter)", "leaf": "$(der leaf)", "leafKeyPkcs8": "$(key leaf)",
  "leafWithoutMarker": "$(der leafplain)",
  "rogueRoot": "$(der rogue)", "rogueRootSha256": "$(fp rogue)",
  "expiredLeaf": "$(der expired)"
}
JSON
echo "wrote apple-test-chain.json"
