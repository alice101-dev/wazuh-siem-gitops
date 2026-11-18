import sys

path = "/var/ossec/wodles/gcloud/pubsub/subscriber.py"
original = "        return pubsub.subscriber.Client.from_service_account_file(credentials_file)  # noqa: E501\n"
patched = (
    "        with open(credentials_file) as file:\n"
    "            credentials = loads(file.read())\n"
    "        if credentials.get('type') == 'service_account':\n"
    "            return pubsub.subscriber.Client.from_service_account_info(credentials)\n"
    "        return pubsub.subscriber.Client()\n"
)

with open(path) as file:
    source = file.read()
if source.count(original) != 1:
    sys.exit(f"{path} no longer contains the expected client factory: the Workload Identity patch does not apply")
with open(path, "w") as file:
    file.write(source.replace(original, patched))
