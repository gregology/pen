"""Audit logging callback for the LLM proxy.

Writes one JSON line per LLM call (success or failure) to
/logs/audit.jsonl, which is bind-mounted to a host path the agent
container cannot access. This is the platform's audit trail, so it is
deliberately dumb: append to a file, no rotation logic, no network.
Log rotation is a host-side concern (e.g. logrotate on /home/user/pen/llm-logs).
"""

import json
import os
import threading
from datetime import datetime, timezone

from litellm.integrations.custom_logger import CustomLogger

LOG_PATH = os.environ.get("LLM_AUDIT_LOG", "/logs/audit.jsonl")

_lock = threading.Lock()


def _append(record: dict) -> None:
    line = json.dumps(record, default=str, ensure_ascii=False)
    with _lock:
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(line + "\n")


class AuditLogger(CustomLogger):
    def _record(self, kwargs, response_obj, start_time, end_time, error=None):
        record = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "model": kwargs.get("model"),
            "litellm_model_name": (kwargs.get("litellm_params") or {}).get(
                "metadata", {}
            ).get("model_name"),
            "messages": kwargs.get("messages"),
            "optional_params": kwargs.get("optional_params"),
            "response": None if error else response_obj,
            "error": None if not error else str(error),
            "start_time": str(start_time),
            "end_time": str(end_time),
        }
        try:
            _append(record)
        except OSError:
            # Fail loud: an unaudited call must not pass silently.
            raise

    def log_success_event(self, kwargs, response_obj, start_time, end_time):
        self._record(kwargs, response_obj, start_time, end_time)

    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        self._record(kwargs, response_obj, start_time, end_time)

    def log_failure_event(self, kwargs, response_obj, start_time, end_time):
        self._record(kwargs, response_obj, start_time, end_time, error=response_obj)

    async def async_log_failure_event(self, kwargs, response_obj, start_time, end_time):
        self._record(kwargs, response_obj, start_time, end_time, error=response_obj)


proxy_handler_instance = AuditLogger()
