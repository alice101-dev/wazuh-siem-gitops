import sys

path = "/var/ossec/wodles/gcloud/pubsub/subscriber.py"
replacements = [
    (
        "from json import dumps, JSONDecodeError, loads\n",
        "from json import dumps, JSONDecodeError, loads\n"
        "from time import monotonic\n"
        "\n"
        "PULL_TIME_BUDGET_SECONDS = 30\n",
    ),
    (
        "        return pubsub.subscriber.Client.from_service_account_file(credentials_file)  # noqa: E501\n",
        "        with open(credentials_file) as file:\n"
        "            credentials = loads(file.read())\n"
        "        if credentials.get('type') == 'service_account':\n"
        "            return pubsub.subscriber.Client.from_service_account_info(credentials)\n"
        "        return pubsub.subscriber.Client()\n",
    ),
    (
        "            processed_messages = 0\n"
        "            pulled_messages = self.pull_request(max_messages)\n"
        "            while pulled_messages > 0 and processed_messages < max_messages:\n",
        "            processed_messages = 0\n"
        "            deadline = monotonic() + PULL_TIME_BUDGET_SECONDS\n"
        "            pulled_messages = self.pull_request(max_messages)\n"
        "            while pulled_messages > 0 and processed_messages < max_messages and monotonic() < deadline:\n",
    ),
]

with open(path) as file:
    source = file.read()
for original, patched in replacements:
    if source.count(original) != 1:
        sys.exit(f"{path} no longer contains the expected code: the collector patch does not apply\n{original}")
    source = source.replace(original, patched)
with open(path, "w") as file:
    file.write(source)
