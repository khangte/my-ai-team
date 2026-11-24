"""프로젝트와 세션에 속한 전송 실패를 기록하고 조회한다."""

import datetime
import json
import os
import sys
import uuid


action, path, project, session, *args = sys.argv[1:]

if action == "record":
    role, message = args
    entry = {
        "id": uuid.uuid4().hex[:16],
        "project": project,
        "session": session,
        "role": role,
        "message": message,
        "time": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    }
    data = (json.dumps(entry, ensure_ascii=False) + "\n").encode()
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, data)
    finally:
        os.close(fd)
    sys.exit(0)

entries = []
try:
    with open(path, encoding="utf-8") as journal:
        for line in journal:
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry["project"] == project and entry["session"] == session:
                entries.append(entry)
except FileNotFoundError:
    pass

if action == "summary":
    summary = {}
    for entry in entries:
        role = entry["role"]
        count, latest = summary.get(role, (0, ""))
        summary[role] = count + 1, max(latest, entry["time"])
    for role, (count, latest) in summary.items():
        print(f"{role}\t{count}\t{latest}")
elif action == "list":
    if not entries:
        print("기록된 전송 실패가 없습니다.")
    for entry in entries:
        message = json.dumps(entry["message"], ensure_ascii=False)
        print(f'{entry["id"]} · {entry["role"]} · {entry["time"]} · {message}')
elif action == "get":
    for entry in entries:
        if entry["id"] == args[0]:
            print(entry["role"], entry["message"], sep="\n")
            break
    else:
        sys.exit("이 프로젝트와 세션에 해당하는 실패 ID가 없습니다.")
