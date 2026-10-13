#!/usr/bin/env python3
"""Offline Ed25519 issuance. The private key belongs on the merchant side only."""
import argparse,base64,json,os,time,uuid
from pathlib import Path
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey,Ed25519PublicKey
def b64(data):return base64.urlsafe_b64encode(data).decode().rstrip('=')
def decode(text):return base64.urlsafe_b64decode(text+'='*((4-len(text)%4)%4))
def issue(private,customer,license_id=None,expiry=None,machine_id=None):
    payload={'product':'parcel','licenseID':license_id or str(uuid.uuid4()),'customer':customer,'issuedAt':int(time.time()),'expiresAt':expiry}
    if machine_id:payload['machineID']=machine_id
    raw=json.dumps(payload,separators=(',',':'),sort_keys=True,ensure_ascii=False).encode()
    return b64(raw)+'.'+b64(private.sign(raw))
def verify(token,public):
    raw,sig=token.split('.');data=decode(raw);public.verify(decode(sig),data)
    payload=json.loads(data)
    if payload.get('product')!='parcel':raise ValueError('Wrong product')
    if payload.get('expiresAt') is not None and time.time()>payload['expiresAt']:raise ValueError('Expired')
    return payload
def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='command',required=True)
    key=sub.add_parser('keygen');key.add_argument('--private',type=Path,required=True)
    mint=sub.add_parser('issue');mint.add_argument('--private',type=Path,required=True);mint.add_argument('--customer',required=True);mint.add_argument('--license-id');mint.add_argument('--expiry',type=int);mint.add_argument('--machine-id',help="Lock this licence to one Mac: paste the customer's Mac ID from Parcel → Preferences → Your licence")
    check=sub.add_parser('verify');check.add_argument('--public',required=True);check.add_argument('--token-file',type=Path,required=True)
    a=p.parse_args()
    if a.command=='keygen':
        private=Ed25519PrivateKey.generate();raw=private.private_bytes(serialization.Encoding.Raw,serialization.PrivateFormat.Raw,serialization.NoEncryption())
        fd=os.open(a.private,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,'wb')as f:f.write(raw)
        public=private.public_key().public_bytes(serialization.Encoding.Raw,serialization.PublicFormat.Raw)
        print(base64.b64encode(public).decode())
    elif a.command=='issue':
        private=Ed25519PrivateKey.from_private_bytes(a.private.read_bytes());print(issue(private,a.customer,a.license_id,a.expiry,a.machine_id))
    else:print(json.dumps(verify(a.token_file.read_text().strip(),Ed25519PublicKey.from_public_bytes(base64.b64decode(a.public,validate=True))),indent=2))
if __name__=='__main__':main()
