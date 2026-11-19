import unittest,importlib.util
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.exceptions import InvalidSignature
spec=importlib.util.spec_from_file_location('license_tool',Path(__file__).parents[1]/'Scripts/license-tool.py')
tool=importlib.util.module_from_spec(spec);spec.loader.exec_module(tool)
class LicenceTests(unittest.TestCase):
 def test_issue_verify_unicode_customer(self):
  key=Ed25519PrivateKey.generate();token=tool.issue(key,'नमस्ते 🌿',license_id='test-order',machine_ids=['mac-a'],plan='two')
  payload=tool.verify(token,key.public_key());self.assertEqual(payload['customer'],'नमस्ते 🌿');self.assertEqual(payload['deviceLimit'],2)
 def test_modified_payload_is_rejected(self):
  key=Ed25519PrivateKey.generate();token=tool.issue(key,'Buyer',machine_ids=['mac-a']);raw,sig=token.split('.')
  data=tool.decode(raw).replace(b'Buyer',b'Other')
  with self.assertRaises(InvalidSignature):tool.verify(tool.b64(data)+'.'+sig,key.public_key())
 def test_wrong_public_key_is_rejected(self):
  key=Ed25519PrivateKey.generate();token=tool.issue(key,'Buyer',machine_ids=['mac-a'])
  with self.assertRaises(InvalidSignature):tool.verify(token,Ed25519PrivateKey.generate().public_key())
 def test_expired_licence_is_rejected(self):
  key=Ed25519PrivateKey.generate();token=tool.issue(key,'Buyer',expiry=1,machine_ids=['mac-a'])
  with self.assertRaises(ValueError):tool.verify(token,key.public_key())
 def test_plan_limit_and_machine_binding_are_required(self):
  key=Ed25519PrivateKey.generate()
  with self.assertRaises(ValueError):tool.issue(key,'Buyer')
  with self.assertRaises(ValueError):tool.issue(key,'Buyer',machine_ids=['a','b'],plan='single')
if __name__=='__main__':unittest.main()
