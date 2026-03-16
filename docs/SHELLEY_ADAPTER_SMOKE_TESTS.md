# Shelley adapter smoke tests

## Goal

Provide a very small local harness for validating the Shelley-to-Stavrobot adapter against a running Stavrobot instance.

## Entry points

### Basic adapter

- `chat-with-stavrobot.sh`

### Machine-oriented client wrapper

- `client-stavrobot.sh`

### Smoke harnesses

- `smoke-test-stavrobot-adapter.sh`
- `smoke-test-stavrobot-client.sh`

## Recommended checks

### 1. Help output

```bash
./chat-with-stavrobot.sh --help
./client-stavrobot.sh --help
./smoke-test-stavrobot-adapter.sh --help
./smoke-test-stavrobot-client.sh --help
```

### 2. Happy path against a running Stavrobot instance

```bash
./smoke-test-stavrobot-adapter.sh --stavrobot-dir /opt/stavrobot
./smoke-test-stavrobot-client.sh --stavrobot-dir /opt/stavrobot
```

### 3. Raw/pretty JSON paths

```bash
./smoke-test-stavrobot-adapter.sh --stavrobot-dir /opt/stavrobot --raw-json
./client-stavrobot.sh --stavrobot-dir /opt/stavrobot health --pretty
./client-stavrobot.sh --stavrobot-dir /opt/stavrobot conversations --pretty
./smoke-test-stavrobot-client.sh --stavrobot-dir /opt/stavrobot --pretty
```

### 4. Failure path: wrong password

```bash
./smoke-test-stavrobot-adapter.sh --base-url http://localhost:8000 --password wrong
./client-stavrobot.sh --base-url http://localhost:8000 --password wrong health
```

Expected result: non-zero exit and a clear auth failure.

### 5. Failure path: service unreachable

```bash
./smoke-test-stavrobot-adapter.sh --base-url http://localhost:19999 --password test
./client-stavrobot.sh --base-url http://localhost:19999 --password test health
```

Expected result: non-zero exit and a clear connectivity failure.

## Notes

- The adapter smoke harness does not attempt to validate exact model output.
- The client smoke harness validates wiring for the richer `/api/client/*` flow by checking that health works and that returned `conversation_id` and `message_id` show up again in listing/history.
- These checks are intended to validate local client wiring and failure handling, not model determinism.
- For deterministic prompts, prefer asking for a short exact-format response.
