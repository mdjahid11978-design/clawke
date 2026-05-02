from __future__ import annotations

import asyncio
import json
import sqlite3
from pathlib import Path

import pytest

from cron_sync import (
    DELIVERY_UNAVAILABLE,
    CronOutputRecord,
    CronSyncConfigStore,
    CronSyncStateStore,
    HermesCronOutputSyncer,
    discover_new_outputs,
    extract_cron_response,
)


class FakeJobsApi:
    def __init__(self, output_dir: Path):
        self.OUTPUT_DIR = output_dir
        self.jobs = []

    def list_jobs(self, include_disabled=False):
        return list(self.jobs)


def _write_output(path: Path, text: str, mtime: float) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    import os

    os.utime(path, (mtime, mtime))


def _rows(db_path: Path) -> list[sqlite3.Row]:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        return conn.execute("SELECT * FROM cron_delivery_state ORDER BY output_filename").fetchall()
    finally:
        conn.close()


def test_config_initializes_when_missing(tmp_path):
    path = tmp_path / "cron-sync.json"
    store = CronSyncConfigStore(path, "hermes")

    data = store.load_or_initialize(1000.5)

    assert data["gateway_id"] == "hermes"
    assert data["last_scanned_mtime"] == 1000.5
    assert json.loads(path.read_text(encoding="utf-8")) == data


def test_config_existing_file_is_not_modified(tmp_path):
    path = tmp_path / "cron-sync.json"
    path.write_text('{"gateway_id":"hermes","last_scanned_mtime":123.0}\n', encoding="utf-8")
    before = path.read_text(encoding="utf-8")
    store = CronSyncConfigStore(path, "hermes")

    data = store.load_or_initialize(999.0)

    assert data["last_scanned_mtime"] == 123.0
    assert path.read_text(encoding="utf-8") == before


def test_state_insert_is_idempotent_and_failure_transitions(tmp_path):
    store = CronSyncStateStore(tmp_path / "cron-sync.db")
    record = CronOutputRecord(
        gateway_id="hermes",
        job_id="job_1",
        output_filename="2026-05-01_17-16-06.md",
        output_path="/tmp/out.md",
        output_mtime=100.0,
        job_name="Daily",
        conversation_id="conv_1",
        discovered_at=101.0,
    )

    assert store.insert_pending_output(record) is True
    assert store.insert_pending_output(record) is False

    due = store.list_due_outputs("hermes", 200.0)
    assert len(due) == 1
    assert store.mark_failed_attempt(due[0], "boom", 200.0) == 1
    row = store.get_record("hermes", "job_1", "2026-05-01_17-16-06.md")
    assert row.status == "pending"
    assert row.attempts == 1
    assert row.next_retry_at == 260.0

    assert store.mark_failed_attempt(row, "boom again", 260.0) == 2
    row = store.get_record("hermes", "job_1", "2026-05-01_17-16-06.md")
    assert row.status == "pending"
    assert row.attempts == 2
    assert row.next_retry_at == 560.0

    assert store.mark_failed_attempt(row, "final", 560.0) == 3
    row = store.get_record("hermes", "job_1", "2026-05-01_17-16-06.md")
    assert row.status == "failed"
    assert row.attempts == 3
    assert row.next_retry_at is None
    store.close()


def test_discover_new_outputs_filters_jobs_and_mtime(tmp_path):
    output_dir = tmp_path / "output"
    _write_output(output_dir / "job_1" / "old.md", "old", 90.0)
    _write_output(output_dir / "job_1" / "new.md", "new", 110.0)
    _write_output(output_dir / "job_2" / "ignored.md", "ignored", 120.0)
    _write_output(output_dir / "unknown" / "unknown.md", "unknown", 130.0)

    records = discover_new_outputs(
        gateway_id="hermes",
        jobs=[
            {"id": "job_1", "name": "Daily", "deliver": "conversation:conv_1"},
            {"id": "job_2", "name": "Local", "deliver": "local"},
        ],
        output_dir=output_dir,
        last_scanned_mtime=100.0,
        now=150.0,
    )

    assert [record.output_filename for record in records] == ["new.md"]
    assert records[0].conversation_id == "conv_1"


def test_extract_cron_response_handles_marker_and_silent():
    assert extract_cron_response("# Cron\n\n## Response\n\nDone") == "Done"
    assert extract_cron_response("No marker") == "No marker"
    assert extract_cron_response("## Response\n\n[SILENT]") == ""


def test_first_run_does_not_backfill_history(tmp_path):
    jobs_api = FakeJobsApi(tmp_path / "output")
    jobs_api.jobs = [{"id": "job_1", "name": "Daily", "deliver": "conversation:conv_1"}]
    _write_output(jobs_api.OUTPUT_DIR / "job_1" / "old.md", "## Response\n\nOld", 900.0)

    syncer = HermesCronOutputSyncer(
        gateway_id="hermes",
        jobs_provider=lambda: jobs_api,
        deliver_result=lambda _job, _body: None,
        send_alert=lambda _alert: None,
        config_path=tmp_path / "cron-sync.json",
        db_path=tmp_path / "cron-sync.db",
    )
    syncer.scan_once(now=1000.0)

    assert json.loads((tmp_path / "cron-sync.json").read_text())["last_scanned_mtime"] == 1000.0
    assert _rows(tmp_path / "cron-sync.db") == []


def test_new_output_is_delivered_and_updates_last_scanned_mtime(tmp_path):
    jobs_api = FakeJobsApi(tmp_path / "output")
    jobs_api.jobs = [{"id": "job_1", "name": "Daily", "deliver": "conversation:conv_1"}]
    (tmp_path / "cron-sync.json").write_text(
        json.dumps({"gateway_id": "hermes", "last_scanned_mtime": 900.0}),
        encoding="utf-8",
    )
    _write_output(jobs_api.OUTPUT_DIR / "job_1" / "new.md", "# Cron\n\n## Response\n\nDone", 950.0)
    delivered = []

    syncer = HermesCronOutputSyncer(
        gateway_id="hermes",
        jobs_provider=lambda: jobs_api,
        deliver_result=lambda job, body: delivered.append((job, body)) or None,
        send_alert=lambda _alert: None,
        config_path=tmp_path / "cron-sync.json",
        db_path=tmp_path / "cron-sync.db",
    )
    syncer.scan_once(now=1000.0)

    assert delivered[0][0]["id"] == "job_1"
    assert delivered[0][1] == "Done"
    assert json.loads((tmp_path / "cron-sync.json").read_text())["last_scanned_mtime"] == 950.0
    rows = _rows(tmp_path / "cron-sync.db")
    assert rows[0]["status"] == "delivered"


def test_no_new_output_leaves_config_unchanged(tmp_path):
    jobs_api = FakeJobsApi(tmp_path / "output")
    jobs_api.jobs = [{"id": "job_1", "name": "Daily", "deliver": "conversation:conv_1"}]
    config_path = tmp_path / "cron-sync.json"
    config_path.write_text(
        json.dumps({"gateway_id": "hermes", "last_scanned_mtime": 900.0}),
        encoding="utf-8",
    )
    before = config_path.read_text(encoding="utf-8")

    syncer = HermesCronOutputSyncer(
        gateway_id="hermes",
        jobs_provider=lambda: jobs_api,
        deliver_result=lambda _job, _body: None,
        send_alert=lambda _alert: None,
        config_path=config_path,
        db_path=tmp_path / "cron-sync.db",
    )
    syncer.scan_once(now=1000.0)

    assert config_path.read_text(encoding="utf-8") == before


def test_pending_row_survives_restart_and_is_delivered(tmp_path):
    jobs_api = FakeJobsApi(tmp_path / "output")
    jobs_api.jobs = [{"id": "job_1", "name": "Daily", "deliver": "conversation:conv_1"}]
    _write_output(jobs_api.OUTPUT_DIR / "job_1" / "new.md", "## Response\n\nDone", 950.0)
    config_path = tmp_path / "cron-sync.json"
    config_path.write_text(
        json.dumps({"gateway_id": "hermes", "last_scanned_mtime": 900.0}),
        encoding="utf-8",
    )

    first = HermesCronOutputSyncer(
        gateway_id="hermes",
        jobs_provider=lambda: jobs_api,
        deliver_result=lambda _job, _body: DELIVERY_UNAVAILABLE,
        send_alert=lambda _alert: None,
        config_path=config_path,
        db_path=tmp_path / "cron-sync.db",
    )
    first.scan_once(now=1000.0)

    delivered = []
    second = HermesCronOutputSyncer(
        gateway_id="hermes",
        jobs_provider=lambda: jobs_api,
        deliver_result=lambda job, body: delivered.append((job, body)) or None,
        send_alert=lambda _alert: None,
        config_path=config_path,
        db_path=tmp_path / "cron-sync.db",
    )
    second.scan_once(now=1005.0)

    assert delivered
    assert _rows(tmp_path / "cron-sync.db")[0]["status"] == "delivered"


def test_failure_attempts_send_alerts_and_stop_after_three(tmp_path):
    jobs_api = FakeJobsApi(tmp_path / "output")
    jobs_api.jobs = [{"id": "job_1", "name": "Daily", "deliver": "conversation:conv_1"}]
    _write_output(jobs_api.OUTPUT_DIR / "job_1" / "new.md", "## Response\n\nDone", 950.0)
    (tmp_path / "cron-sync.json").write_text(
        json.dumps({"gateway_id": "hermes", "last_scanned_mtime": 900.0}),
        encoding="utf-8",
    )
    alerts = []
    syncer = HermesCronOutputSyncer(
        gateway_id="hermes",
        jobs_provider=lambda: jobs_api,
        deliver_result=lambda _job, _body: "boom",
        send_alert=alerts.append,
        config_path=tmp_path / "cron-sync.json",
        db_path=tmp_path / "cron-sync.db",
    )

    syncer.scan_once(now=1000.0)
    row = _rows(tmp_path / "cron-sync.db")[0]
    assert row["attempts"] == 1
    assert row["next_retry_at"] == 1060.0
    assert len(alerts) == 1

    syncer.scan_once(now=1060.0)
    row = _rows(tmp_path / "cron-sync.db")[0]
    assert row["attempts"] == 2
    assert row["next_retry_at"] == 1360.0
    assert len(alerts) == 2

    syncer.scan_once(now=1360.0)
    row = _rows(tmp_path / "cron-sync.db")[0]
    assert row["status"] == "failed"
    assert row["attempts"] == 3
    assert len(alerts) == 3
    assert "Automatic delivery has stopped" in alerts[-1]["message"]


def test_delivery_unavailable_does_not_consume_attempt(tmp_path):
    jobs_api = FakeJobsApi(tmp_path / "output")
    jobs_api.jobs = [{"id": "job_1", "name": "Daily", "deliver": "conversation:conv_1"}]
    _write_output(jobs_api.OUTPUT_DIR / "job_1" / "new.md", "## Response\n\nDone", 950.0)
    (tmp_path / "cron-sync.json").write_text(
        json.dumps({"gateway_id": "hermes", "last_scanned_mtime": 900.0}),
        encoding="utf-8",
    )
    alerts = []

    syncer = HermesCronOutputSyncer(
        gateway_id="hermes",
        jobs_provider=lambda: jobs_api,
        deliver_result=lambda _job, _body: DELIVERY_UNAVAILABLE,
        send_alert=alerts.append,
        config_path=tmp_path / "cron-sync.json",
        db_path=tmp_path / "cron-sync.db",
    )
    syncer.scan_once(now=1000.0)

    row = _rows(tmp_path / "cron-sync.db")[0]
    assert row["attempts"] == 0
    assert row["status"] == "pending"
    assert alerts == []


@pytest.mark.asyncio
async def test_start_scans_in_executor_without_sqlite_thread_error(tmp_path):
    jobs_api = FakeJobsApi(tmp_path / "output")
    jobs_api.jobs = [{"id": "job_1", "name": "Daily", "deliver": "conversation:conv_1"}]
    _write_output(jobs_api.OUTPUT_DIR / "job_1" / "new.md", "## Response\n\nDone", 950.0)
    (tmp_path / "cron-sync.json").write_text(
        json.dumps({"gateway_id": "hermes", "last_scanned_mtime": 900.0}),
        encoding="utf-8",
    )
    delivered = []
    syncer = HermesCronOutputSyncer(
        gateway_id="hermes",
        jobs_provider=lambda: jobs_api,
        deliver_result=lambda job, body: delivered.append((job, body)) or None,
        send_alert=lambda _alert: None,
        config_path=tmp_path / "cron-sync.json",
        db_path=tmp_path / "cron-sync.db",
        poll_interval_seconds=0.01,
    )
    task = asyncio.create_task(syncer.start())
    try:
        for _ in range(50):
            if delivered:
                break
            await asyncio.sleep(0.02)
        assert delivered
    finally:
        await syncer.stop()
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass
