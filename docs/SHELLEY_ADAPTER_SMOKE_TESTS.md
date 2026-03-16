# Shelley adapter smoke tests

## Goal

Provide a very small local harness for validating the Shelley-to-Stavrobot adapter against a running Stavrobot instance.

## Entry points

### Basic adapter

- `chat-with-stavrobot.sh`

### Smoke harness

- `smoke-test-stavrobot-adapter.sh`

## Recommended checks

### 1. Help output

```bash
./chat-with-stavrobot.sh --help
./smoke-test-stavrobot-adapter.sh --help
```

### 2. Happy path against a running Stavrobot instance

```bash
./smoke-test-stavrobot-adapter.sh --stavrobot-dir /opt/stavrobot
```

### 3. Raw JSON path

```bash
./smoke-test-stavrobot-adapter.sh --stavrobot-dir /opt/stavrobot --raw-json
```

### 4. Failure path: wrong password

```bash
./smoke-test-stavrobot-adapter.sh --base-url http://localhost:8000 --password wrong
```

Expected result: non-zero exit and a clear auth failure.

### 5. Failure path: service unreachable

```bash
./smoke-test-stavrobot-adapter.sh --base-url http://localhost:19999 --password test
```

Expected result: non-zero exit and a clear connectivity failure.

## Notes

- The smoke harness does not attempt to validate exact model output.
- It is intended to validate adapter wiring and failure handling.
- For deterministic prompts, prefer asking for a short exact-format response.
