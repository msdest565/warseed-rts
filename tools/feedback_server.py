#!/usr/bin/env python3
"""WARSEED temporary playtest feedback collector. Standard library only."""

from __future__ import annotations

import argparse
import csv
import html
import io
import json
import os
import re
import tempfile
import threading
from collections import Counter
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

MAX_BODY_BYTES = 256 * 1024
FEEDBACK_ID = re.compile(r"^[a-zA-Z0-9_-]{1,96}$")
lock = threading.Lock()
AREA_LABELS = {
    "units": "兵种类型与战场定位",
    "maps": "地图大小、地形与导航",
    "economy": "经济、补给与增援",
    "cards": "部队卡、战法与成长",
    "objectives": "任务目标与胜利条件",
    "commander_ai": "将领 Agent 与委托指挥",
    "campaign_story": "战役地图、进程与剧情",
    "controls_ui": "操作、界面与可读性",
    "pacing_balance": "节奏、难度与平衡",
}


def read_submissions(data_directory: Path) -> list[dict]:
    records: list[dict] = []
    submissions = data_directory / "submissions"
    if not submissions.exists():
        return records
    for path in sorted(submissions.rglob("*.json")):
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                records.append(value)
        except (OSError, json.JSONDecodeError):
            continue
    return records


def validate(payload: object) -> list[str]:
    if not isinstance(payload, dict):
        return ["request body must be a JSON object"]
    errors: list[str] = []
    if payload.get("format_version") != 1:
        errors.append("unsupported format_version")
    feedback_id = payload.get("feedback_id")
    if not isinstance(feedback_id, str) or not FEEDBACK_ID.fullmatch(feedback_id):
        errors.append("invalid feedback_id")
    responses = payload.get("responses")
    if not isinstance(responses, dict):
        errors.append("responses must be an object")
        return errors
    if type(responses.get("overall_rating")) is not int or responses["overall_rating"] not in (1, 2, 3, 4, 5):
        errors.append("overall_rating must be 1-5")
    if not isinstance(responses.get("priority_area"), str) or not responses["priority_area"]:
        errors.append("priority_area is required")
    if not isinstance(responses.get("biggest_problem"), str) or not responses["biggest_problem"].strip():
        errors.append("biggest_problem is required")
    for key in ("best_part", "biggest_problem", "suggestions", "bug_details"):
        if len(str(responses.get(key, ""))) > 4000:
            errors.append(f"{key} exceeds 4000 characters")
    return errors


def save_submission(data_directory: Path, payload: dict) -> tuple[Path, bool]:
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    target_directory = data_directory / "submissions" / day
    target_directory.mkdir(parents=True, exist_ok=True)
    target = target_directory / f"{payload['feedback_id']}.json"
    with lock:
        if target.exists():
            return target, True
        fd, temporary_name = tempfile.mkstemp(prefix=".feedback-", suffix=".tmp", dir=target_directory)
        try:
            with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
                json.dump(payload, stream, ensure_ascii=False, indent=2)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary_name, target)
        finally:
            if os.path.exists(temporary_name):
                os.unlink(temporary_name)
    return target, False


def summarize(records: list[dict]) -> dict:
    ratings: list[int] = []
    priorities: Counter[str] = Counter()
    scenarios: Counter[str] = Counter()
    outcomes: Counter[str] = Counter()
    bugs = 0
    for record in records:
        responses = record.get("responses", {})
        rating = responses.get("overall_rating")
        if isinstance(rating, int) and 1 <= rating <= 5:
            ratings.append(rating)
        priorities[str(responses.get("priority_area", "unknown"))] += 1
        scenarios[str(record.get("scenario_id", "unknown"))] += 1
        outcomes[str(record.get("outcome", "unknown"))] += 1
        bugs += int(bool(responses.get("encountered_bug", False)))
    return {
        "submission_count": len(records),
        "average_overall_rating": round(sum(ratings) / len(ratings), 2) if ratings else None,
        "bug_report_count": bugs,
        "priority_areas": dict(priorities.most_common()),
        "scenarios": dict(scenarios.most_common()),
        "outcomes": dict(outcomes.most_common()),
        "generated_utc": datetime.now(timezone.utc).isoformat(),
    }


def csv_export(records: list[dict]) -> bytes:
    fields = [
        "feedback_id", "submitted_utc", "build_id", "anonymous_session_id", "scenario_id", "outcome",
        "overall_rating", "objective_clarity", "controls_clarity", "agent_usefulness", "priority_area",
        "best_part", "biggest_problem", "suggestions", "encountered_bug", "bug_details",
    ]
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=fields)
    writer.writeheader()
    for record in records:
        row = {key: record.get(key, "") for key in fields}
        responses = record.get("responses", {})
        for key in fields:
            if key in responses:
                row[key] = responses[key]
        writer.writerow(row)
    return stream.getvalue().encode("utf-8-sig")


def dashboard(records: list[dict]) -> bytes:
    summary = summarize(records)
    priority_rows = "".join(
        f"<tr><td>{html.escape(AREA_LABELS.get(key, key))}</td><td>{value}</td></tr>"
        for key, value in summary["priority_areas"].items()
    ) or "<tr><td colspan='2'>No submissions</td></tr>"
    recent_rows = []
    for record in reversed(records[-50:]):
        responses = record.get("responses", {})
        recent_rows.append(
            "<tr>"
            f"<td>{html.escape(str(record.get('submitted_utc', '')))}</td>"
            f"<td>{html.escape(str(record.get('scenario_id', '')))}</td>"
            f"<td>{html.escape(str(responses.get('overall_rating', '')))}</td>"
            f"<td>{html.escape(AREA_LABELS.get(str(responses.get('priority_area', '')), str(responses.get('priority_area', ''))))}</td>"
            f"<td>{html.escape(str(responses.get('biggest_problem', '')))}</td>"
            "</tr>"
        )
    recent = "".join(recent_rows) or "<tr><td colspan='5'>No submissions</td></tr>"
    average = summary["average_overall_rating"] if summary["average_overall_rating"] is not None else "-"
    page = f"""<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>WARSEED Feedback</title><style>
body{{font:14px system-ui;margin:0;background:#101516;color:#e5ece8}}main{{max-width:1180px;margin:auto;padding:24px}}
h1,h2{{font-weight:600;letter-spacing:0}}.stats{{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}}
.stat{{border:1px solid #52605d;padding:14px;background:#18201f}}.value{{font-size:26px;color:#f2c747}}
table{{width:100%;border-collapse:collapse;background:#151c1b}}th,td{{border:1px solid #3e4a47;padding:8px;text-align:left;vertical-align:top}}
th{{color:#76cabe}}a{{color:#76cabe}}@media(max-width:700px){{.stats{{grid-template-columns:1fr}}main{{padding:10px}}}}
</style></head><body><main><h1>WARSEED 试玩反馈</h1>
<div class="stats"><div class="stat"><div>反馈数量</div><div class="value">{summary['submission_count']}</div></div>
<div class="stat"><div>平均评分</div><div class="value">{average}</div></div>
<div class="stat"><div>错误报告</div><div class="value">{summary['bug_report_count']}</div></div></div>
<p><a href="/export.csv">下载 CSV</a> · <a href="/api/summary">查看 JSON 汇总</a></p>
<h2>优先完善板块</h2><table><tr><th>板块 ID</th><th>票数</th></tr>{priority_rows}</table>
<h2>最近反馈</h2><table><tr><th>时间</th><th>关卡</th><th>评分</th><th>优先板块</th><th>主要问题</th></tr>{recent}</table>
</main></body></html>"""
    return page.encode("utf-8")


class FeedbackHandler(BaseHTTPRequestHandler):
    server_version = "WARSEEDFeedback/1"

    @property
    def data_directory(self) -> Path:
        return self.server.data_directory  # type: ignore[attr-defined]

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        records = read_submissions(self.data_directory)
        if path == "/health":
            self.send_json(200, {"status": "ok", "submission_count": len(records)})
        elif path == "/api/summary":
            self.send_json(200, summarize(records))
        elif path == "/export.csv":
            body = csv_export(records)
            self.send_body(200, body, "text/csv; charset=utf-8", "attachment; filename=warseed-feedback.csv")
        elif path in ("/", "/dashboard"):
            self.send_body(200, dashboard(records), "text/html; charset=utf-8")
        else:
            self.send_json(404, {"error": "not_found"})

    def do_POST(self) -> None:
        if urlparse(self.path).path != "/feedback":
            self.send_json(404, {"error": "not_found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_json(400, {"error": "invalid_content_length"})
            return
        if length <= 0 or length > MAX_BODY_BYTES:
            self.send_json(413, {"error": "body_size", "max_bytes": MAX_BODY_BYTES})
            return
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self.send_json(400, {"error": "invalid_json"})
            return
        errors = validate(payload)
        if errors:
            self.send_json(422, {"error": "validation", "details": errors})
            return
        target, duplicate = save_submission(self.data_directory, payload)
        self.send_json(200 if duplicate else 201, {
            "status": "duplicate" if duplicate else "stored",
            "feedback_id": payload["feedback_id"],
            "stored_file": str(target.relative_to(self.data_directory)).replace("\\", "/"),
        })

    def send_json(self, status: int, payload: dict) -> None:
        self.send_body(status, json.dumps(payload, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

    def send_body(self, status: int, body: bytes, content_type: str, disposition: str | None = None) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        if disposition:
            self.send_header("Content-Disposition", disposition)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        print(f"[{self.log_date_time_string()}] {self.address_string()} {format % args}")


def main() -> None:
    parser = argparse.ArgumentParser(description="WARSEED temporary feedback collector")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--data-directory", required=True)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("port must be 1-65535")
    data_directory = Path(args.data_directory).resolve()
    data_directory.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer((args.host, args.port), FeedbackHandler)
    server.data_directory = data_directory  # type: ignore[attr-defined]
    print(f"WARSEED feedback server: http://{args.host}:{args.port}/dashboard")
    print(f"POST endpoint: http://{args.host}:{args.port}/feedback")
    print(f"Data directory: {data_directory}")
    print("Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
