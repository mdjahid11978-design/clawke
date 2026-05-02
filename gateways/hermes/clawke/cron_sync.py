"""Hermes cron output sync for Clawke Gateway."""

from __future__ import annotations

import asyncio
import json
import logging
import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, Optional

logger = logging.getLogger(__name__)

DELIVERY_UNAVAILABLE = "delivery_unavailable"
MAX_ATTEMPTS = 3


class CronSyncConfigError(Exception):
    """Raised when cron sync JSON config is unreadable."""


def default_sync_dir() -> Path:
    return Path.home() / ".clawke" / "gateway" / "hermes"


def default_db_path() -> Path:
    return default_sync_dir() / "cron-sync.db"


def default_config_path() -> Path:
    return default_sync_dir() / "cron-sync.json"


@dataclass(frozen=True)
class CronJobTarget:
    job_id: str
    job_name: str
    conversation_id: str


@dataclass(frozen=True)
class CronOutputRecord:
    gateway_id: str
    job_id: str
    output_filename: str
    output_path: str
    output_mtime: float
    job_name: str
    conversation_id: str
    discovered_at: float


@dataclass(frozen=True)
class CronDeliveryRecord:
    gateway_id: str
    job_id: str
    output_filename: str
    output_path: str
    output_mtime: float
    job_name: str
    conversation_id: str
    status: str
    attempts: int
    next_retry_at: float | None
    last_error: str | None
    discovered_at: float
    last_attempt_at: float | None
    delivered_at: float | None


DeliveryCallback = Callable[[Dict[str, Any], str], Optional[str]]
AlertCallback = Callable[[Dict[str, Any]], None]
JobsProvider = Callable[[], Any]


def parse_conversation_delivery(deliver: Any) -> str | None:
    if isinstance(deliver, dict):
        target = str(deliver.get("to") or deliver.get("channel") or "")
    else:
        target = str(deliver or "")
    if not target.startswith("conversation:"):
        return None
    conversation_id = target.split(":", 1)[1].strip()
    return conversation_id or None


def extract_cron_response(text: str) -> str:
    marker = "## Response"
    if marker in text:
        text = text.split(marker, 1)[1]
    result = text.strip()
    if "[SILENT]" in result.upper():
        return ""
    return result


def discover_new_outputs(
    gateway_id: str,
    jobs: Iterable[dict[str, Any]],
    output_dir: Path,
    last_scanned_mtime: float,
    now: float,
) -> list[CronOutputRecord]:
    records: list[CronOutputRecord] = []
    for job in jobs:
        job_id = str(job.get("id") or job.get("job_id") or "")
        conversation_id = parse_conversation_delivery(job.get("deliver"))
        if not conversation_id or not _is_safe_id(job_id):
            continue

        job_dir = output_dir / job_id
        if not job_dir.is_dir():
            continue

        for path in job_dir.glob("*.md"):
            try:
                stat = path.stat()
            except OSError:
                continue
            if stat.st_mtime <= last_scanned_mtime:
                continue
            records.append(CronOutputRecord(
                gateway_id=gateway_id,
                job_id=job_id,
                output_filename=path.name,
                output_path=str(path),
                output_mtime=stat.st_mtime,
                job_name=str(job.get("name") or job_id),
                conversation_id=conversation_id,
                discovered_at=now,
            ))
    records.sort(key=lambda item: (item.output_mtime, item.output_filename))
    return records


def _is_safe_id(value: str) -> bool:
    if not value or value in {".", ".."}:
        return False
    path = Path(value)
    return not path.is_absolute() and len(path.parts) == 1 and path.parts[0] == value


class CronSyncConfigStore:
    def __init__(self, path: Path, gateway_id: str):
        self.path = path
        self.gateway_id = gateway_id

    def load_or_initialize(self, now: float) -> dict[str, Any]:
        if not self.path.exists():
            return self.reinitialize(now)
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            raise CronSyncConfigError(str(exc)) from exc
        if not isinstance(data, dict) or "last_scanned_mtime" not in data:
            raise CronSyncConfigError("missing last_scanned_mtime")
        return data

    def reinitialize(self, now: float) -> dict[str, Any]:
        data = {"gateway_id": self.gateway_id, "last_scanned_mtime": now}
        self._write(data)
        return data

    def update_last_scanned_mtime(self, mtime: float) -> None:
        data = self.load_or_initialize(mtime)
        data["gateway_id"] = self.gateway_id
        data["last_scanned_mtime"] = mtime
        self._write(data)

    def _write(self, data: dict[str, Any]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = self.path.with_suffix(".json.tmp")
        tmp_path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        tmp_path.replace(self.path)


class CronSyncStateStore:
    def __init__(self, path: Path):
        self.path = path
        self._conn: sqlite3.Connection | None = None

    def connect(self) -> None:
        if self._conn is not None:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(self.path), check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.executescript("""
            CREATE TABLE IF NOT EXISTS cron_delivery_state (
              gateway_id TEXT NOT NULL,
              job_id TEXT NOT NULL,
              output_filename TEXT NOT NULL,
              output_path TEXT NOT NULL,
              output_mtime REAL NOT NULL,
              job_name TEXT,
              conversation_id TEXT NOT NULL,
              status TEXT NOT NULL CHECK (status IN ('pending', 'delivered', 'failed')),
              attempts INTEGER NOT NULL DEFAULT 0,
              next_retry_at REAL,
              last_error TEXT,
              discovered_at REAL NOT NULL,
              last_attempt_at REAL,
              delivered_at REAL,
              PRIMARY KEY (gateway_id, job_id, output_filename)
            );

            CREATE INDEX IF NOT EXISTS idx_cron_delivery_due
              ON cron_delivery_state (gateway_id, status, next_retry_at, attempts);
        """)
        self._conn.commit()

    def close(self) -> None:
        if self._conn is not None:
            self._conn.close()
            self._conn = None

    def insert_pending_output(self, record: CronOutputRecord) -> bool:
        conn = self._connection()
        cur = conn.execute(
            """
            INSERT OR IGNORE INTO cron_delivery_state (
              gateway_id, job_id, output_filename, output_path, output_mtime,
              job_name, conversation_id, status, attempts, next_retry_at,
              last_error, discovered_at, last_attempt_at, delivered_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', 0, NULL, NULL, ?, NULL, NULL)
            """,
            (
                record.gateway_id,
                record.job_id,
                record.output_filename,
                record.output_path,
                record.output_mtime,
                record.job_name,
                record.conversation_id,
                record.discovered_at,
            ),
        )
        conn.commit()
        return cur.rowcount > 0

    def mark_manual_output_delivered(self, record: CronOutputRecord, now: float) -> None:
        self.insert_pending_output(record)
        self.mark_delivered(self.get_record(record.gateway_id, record.job_id, record.output_filename), now)

    def get_record(self, gateway_id: str, job_id: str, output_filename: str) -> CronDeliveryRecord:
        row = self._connection().execute(
            """
            SELECT * FROM cron_delivery_state
            WHERE gateway_id = ? AND job_id = ? AND output_filename = ?
            """,
            (gateway_id, job_id, output_filename),
        ).fetchone()
        if row is None:
            raise KeyError(f"cron delivery record not found: {gateway_id}/{job_id}/{output_filename}")
        return self._row_to_record(row)

    def list_due_outputs(self, gateway_id: str, now: float) -> list[CronDeliveryRecord]:
        rows = self._connection().execute(
            """
            SELECT * FROM cron_delivery_state
            WHERE gateway_id = ?
              AND status = 'pending'
              AND attempts < ?
              AND (next_retry_at IS NULL OR next_retry_at <= ?)
            ORDER BY discovered_at ASC, output_mtime ASC, output_filename ASC
            """,
            (gateway_id, MAX_ATTEMPTS, now),
        ).fetchall()
        return [self._row_to_record(row) for row in rows]

    def mark_delivered(self, record: CronDeliveryRecord, now: float) -> None:
        self._connection().execute(
            """
            UPDATE cron_delivery_state
            SET status = 'delivered',
                next_retry_at = NULL,
                last_error = NULL,
                delivered_at = ?
            WHERE gateway_id = ? AND job_id = ? AND output_filename = ?
            """,
            (now, record.gateway_id, record.job_id, record.output_filename),
        )
        self._connection().commit()

    def mark_failed_attempt(self, record: CronDeliveryRecord, error: str, now: float) -> int:
        attempts = int(record.attempts) + 1
        if attempts >= MAX_ATTEMPTS:
            status = "failed"
            next_retry_at = None
        elif attempts == 1:
            status = "pending"
            next_retry_at = now + 60
        else:
            status = "pending"
            next_retry_at = now + 300

        self._connection().execute(
            """
            UPDATE cron_delivery_state
            SET status = ?,
                attempts = ?,
                next_retry_at = ?,
                last_error = ?,
                last_attempt_at = ?
            WHERE gateway_id = ? AND job_id = ? AND output_filename = ?
            """,
            (
                status,
                attempts,
                next_retry_at,
                error,
                now,
                record.gateway_id,
                record.job_id,
                record.output_filename,
            ),
        )
        self._connection().commit()
        return attempts

    def _connection(self) -> sqlite3.Connection:
        if self._conn is None:
            self.connect()
        assert self._conn is not None
        return self._conn

    @staticmethod
    def _row_to_record(row: sqlite3.Row) -> CronDeliveryRecord:
        return CronDeliveryRecord(
            gateway_id=str(row["gateway_id"]),
            job_id=str(row["job_id"]),
            output_filename=str(row["output_filename"]),
            output_path=str(row["output_path"]),
            output_mtime=float(row["output_mtime"]),
            job_name=str(row["job_name"] or ""),
            conversation_id=str(row["conversation_id"]),
            status=str(row["status"]),
            attempts=int(row["attempts"]),
            next_retry_at=row["next_retry_at"],
            last_error=row["last_error"],
            discovered_at=float(row["discovered_at"]),
            last_attempt_at=row["last_attempt_at"],
            delivered_at=row["delivered_at"],
        )


class HermesCronOutputSyncer:
    def __init__(
        self,
        gateway_id: str,
        jobs_provider: JobsProvider,
        deliver_result: DeliveryCallback,
        send_alert: AlertCallback,
        config_path: Path | None = None,
        db_path: Path | None = None,
        poll_interval_seconds: float = 5.0,
    ):
        self.gateway_id = gateway_id
        self._jobs_provider = jobs_provider
        self._deliver_result = deliver_result
        self._send_alert = send_alert
        self._config = CronSyncConfigStore(config_path or default_config_path(), gateway_id)
        self._state = CronSyncStateStore(db_path or default_db_path())
        self._poll_interval_seconds = poll_interval_seconds
        self._running = False

    async def start(self) -> None:
        self._running = True
        while self._running:
            try:
                loop = asyncio.get_event_loop()
                await loop.run_in_executor(None, self.scan_once)
            except Exception as exc:
                logger.warning("Hermes cron sync scan failed: %s", exc)
            await asyncio.sleep(self._poll_interval_seconds)

    async def stop(self) -> None:
        self._running = False
        self._state.close()

    def scan_once(self, now: float | None = None) -> None:
        current_time = now if now is not None else time.time()
        self._state.connect()
        try:
            config = self._config.load_or_initialize(current_time)
        except CronSyncConfigError as exc:
            self._safe_alert({
                "severity": "error",
                "source": "cron_sync_config",
                "title": "Hermes cron sync config reset",
                "message": f"Hermes cron sync config was invalid and has been reset.\nError: {exc}",
                "dedupe_key": f"cron_sync_config:{int(current_time)}",
                "metadata": {"error": str(exc)},
            })
            self._config.reinitialize(current_time)
            return

        last_scanned_mtime = float(config.get("last_scanned_mtime") or current_time)
        jobs_api = self._jobs_provider()
        try:
            jobs = jobs_api.list_jobs(include_disabled=True)
        except TypeError:
            jobs = jobs_api.list_jobs()

        output_dir = Path(jobs_api.OUTPUT_DIR)
        discovered = discover_new_outputs(
            gateway_id=self.gateway_id,
            jobs=jobs,
            output_dir=output_dir,
            last_scanned_mtime=last_scanned_mtime,
            now=current_time,
        )

        inserted: list[CronOutputRecord] = []
        for record in discovered:
            if self._state.insert_pending_output(record):
                inserted.append(record)
        if inserted:
            self._config.update_last_scanned_mtime(max(item.output_mtime for item in inserted))

        for record in self._state.list_due_outputs(self.gateway_id, current_time):
            self._attempt_delivery(record, current_time)

    def mark_manual_output_delivered(self, job: dict[str, Any], output_path: Path) -> None:
        conversation_id = parse_conversation_delivery(job.get("deliver"))
        job_id = str(job.get("id") or job.get("job_id") or "")
        if not conversation_id or not _is_safe_id(job_id):
            return
        stat = output_path.stat()
        now = time.time()
        record = CronOutputRecord(
            gateway_id=self.gateway_id,
            job_id=job_id,
            output_filename=output_path.name,
            output_path=str(output_path),
            output_mtime=stat.st_mtime,
            job_name=str(job.get("name") or job_id),
            conversation_id=conversation_id,
            discovered_at=now,
        )
        self._state.connect()
        self._state.mark_manual_output_delivered(record, now)

    def _attempt_delivery(self, record: CronDeliveryRecord, now: float) -> None:
        try:
            text = Path(record.output_path).read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            self._record_failure(record, f"output file missing: {exc}", now)
            return

        body = extract_cron_response(text)
        if not body:
            self._state.mark_delivered(record, now)
            return

        error = self._deliver_result({
            "id": record.job_id,
            "name": record.job_name,
            "deliver": f"conversation:{record.conversation_id}",
        }, body)
        if error is None:
            self._state.mark_delivered(record, now)
            return
        if error == DELIVERY_UNAVAILABLE:
            return
        self._record_failure(record, error, now)

    def _record_failure(self, record: CronDeliveryRecord, error: str, now: float) -> None:
        attempts = self._state.mark_failed_attempt(record, error, now)
        self._safe_alert(self._build_delivery_alert(record, error, attempts))

    def _build_delivery_alert(
        self,
        record: CronDeliveryRecord,
        error: str,
        attempts: int,
    ) -> dict[str, Any]:
        stopped = attempts >= MAX_ATTEMPTS
        final_line = (
            "Automatic delivery has stopped. Please check the task delivery conversation or Gateway connection."
            if stopped
            else f"The next retry is scheduled automatically. Delivery stops after {MAX_ATTEMPTS} failed attempts."
        )
        message = "\n".join([
            "Hermes cron result delivery failed.",
            "",
            f"Job: {record.job_name or record.job_id}",
            f"Job ID: {record.job_id}",
            f"Output: {record.output_filename}",
            f"Target conversation: conversation:{record.conversation_id}",
            f"Attempt: {attempts} / {MAX_ATTEMPTS}",
            f"Error: {error}",
            "",
            final_line,
        ])
        return {
            "severity": "error",
            "source": "cron_delivery",
            "title": "Hermes cron delivery failed",
            "message": message,
            "target_conversation_id": record.conversation_id,
            "dedupe_key": f"cron_delivery:{record.job_id}:{record.output_filename}:attempt:{attempts}",
            "metadata": {
                "job_id": record.job_id,
                "job_name": record.job_name,
                "output_filename": record.output_filename,
                "attempts": attempts,
                "max_attempts": MAX_ATTEMPTS,
            },
        }

    def _safe_alert(self, alert: dict[str, Any]) -> None:
        try:
            self._send_alert(alert)
        except Exception as exc:
            logger.warning("Hermes cron sync alert failed: %s", exc)
