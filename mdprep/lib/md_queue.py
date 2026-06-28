#!/usr/bin/env python3
"""
md_queue.py — Yerel GROMACS iş kuyruğu (rg16.py tarzı)

  jobs.json + PID + arka plan grompp/mdrun
  TRUBA/sbatch gerekmez; iş istasyonunda ./md queue ile kullanılır.
"""
from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

PHASES = ("em", "nvt", "npt", "md")
PREV_PHASE = {"nvt": "em", "npt": "nvt", "md": "npt"}


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def paths() -> dict[str, Path]:
    mdprep_env = _env("MDQUEUE_MDPREP_DIR", "")
    if mdprep_env:
        mdprep = Path(mdprep_env).resolve()
    else:
        mdprep = Path(__file__).resolve().parent.parent
    workdir = Path(_env("MDQUEUE_WORKDIR", _env("WORKDIR", mdprep.parent))).resolve()
    state = Path(_env("MDQUEUE_STATE_DIR", mdprep / ".state")).resolve()
    log_root = Path(_env("MDQUEUE_LOG_DIR", mdprep / "logs" / "queue")).resolve()
    jobs_file = Path(_env("MDQUEUE_JOBS_FILE", state / "jobs.json"))
    return {
        "mdprep": mdprep,
        "workdir": workdir,
        "state": state,
        "log_root": log_root,
        "jobs_file": jobs_file,
    }


def gmx_settings() -> dict[str, str]:
    return {
        "gmx": _env("MDQUEUE_GMX", "gmx"),
        "mdrun_extra": _env("MDQUEUE_MDRUN_EXTRA", ""),
        "maxwarn": _env("MDQUEUE_MAXWARN", "15"),
        "em_mdp": _env("MDQUEUE_EM_MDP", "em.mdp"),
        "solv_ions": _env("MDQUEUE_SOLV_IONS", "solv_ions.gro"),
        "top": _env("MDQUEUE_TOP", "topol.top"),
        "ndx": _env("MDQUEUE_NDX", "index.ndx"),
        "em_gro": _env("MDQUEUE_EM_GRO", "em.gro"),
        "nvt_deffnm": _env("MDQUEUE_NVT_DEFFNM", "nvt"),
        "npt_deffnm": _env("MDQUEUE_NPT_DEFFNM", "npt"),
        "prod_deffnm": _env("MDQUEUE_PROD_DEFFNM", "md_0_1"),
        "run_script": _env("MDQUEUE_RUN_SCRIPT", ""),
    }


def load_jobs(jobs_file: Path) -> list[dict[str, Any]]:
    for attempt in range(10):
        if not jobs_file.exists():
            if attempt >= 9:
                return []
            time.sleep(0.2)
            continue
        try:
            with jobs_file.open("r", encoding="utf-8") as f:
                data = json.load(f)
            return data if isinstance(data, list) else []
        except (json.JSONDecodeError, OSError):
            if attempt >= 9:
                return []
            time.sleep(0.2)
    return []


def save_jobs(jobs_file: Path, jobs: list[dict[str, Any]]) -> None:
    jobs_file.parent.mkdir(parents=True, exist_ok=True)
    tmp = jobs_file.with_suffix(".json.tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(jobs, f, indent=2, ensure_ascii=False)
    tmp.replace(jobs_file)


def next_job_id(jobs: list[dict[str, Any]], phase: str) -> str:
    """em | nvt | npt | md — aynı faz tekrarlanırsa em_2, nvt_2 …"""
    base = phase.lower()
    nums: list[int] = []
    for job in jobs:
        jid = job.get("job_id", "")
        if jid == base:
            nums.append(1)
        elif jid.startswith(f"{base}_") and jid[len(base) + 1 :].isdigit():
            nums.append(int(jid[len(base) + 1 :]))
    n = max(nums, default=0) + 1
    return base if n == 1 else f"{base}_{n}"


def format_duration(seconds: float) -> str:
    delta = timedelta(seconds=int(max(0, seconds)))
    parts: list[str] = []
    if delta.days:
        parts.append(f"{delta.days}d")
    hours, rem = divmod(delta.seconds, 3600)
    if hours:
        parts.append(f"{hours}h")
    minutes, secs = divmod(rem, 60)
    if minutes:
        parts.append(f"{minutes}m")
    if secs or not parts:
        parts.append(f"{secs}s")
    return " ".join(parts)


def expected_output(phase: str, cfg: dict[str, str]) -> str:
    if phase == "em":
        return cfg["em_gro"]
    if phase == "nvt":
        return f"{cfg['nvt_deffnm']}.gro"
    if phase == "npt":
        return f"{cfg['npt_deffnm']}.gro"
    if phase == "md":
        return f"{cfg['prod_deffnm']}.gro"
    raise ValueError(f"unknown phase: {phase}")


def _log_has_fatal(log_file: Path) -> bool:
    if not log_file.exists():
        return False
    try:
        text = log_file.read_text(encoding="utf-8", errors="replace").lower()
    except OSError:
        return True
    markers = ("fatal error", "error in user input", "gromacs terminated", "segmentation fault")
    return any(m in text for m in markers)


def _log_has_ok(log_file: Path) -> bool:
    if not log_file.exists():
        return False
    try:
        text = log_file.read_text(encoding="utf-8", errors="replace").lower()
    except OSError:
        return False
    return "mdrun done" in text or "job_finished" in text


def pid_alive(pid: int | None) -> bool:
    if not pid or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def resolve_status(job: dict[str, Any], workdir: Path, cfg: dict[str, str]) -> str:
    status = job.get("status", "Unknown")
    if status != "Running":
        return status

    pid = job.get("pid")
    phase = job.get("phase", "")
    log_file = Path(job.get("log_file", ""))
    out = workdir / expected_output(phase, cfg)

    if pid_alive(pid):
        return "Running"

    if _log_has_fatal(log_file):
        return "Failed"
    if out.exists() or _log_has_ok(log_file):
        return "Finished"
    return "Failed"


def refresh_jobs(jobs: list[dict[str, Any]], workdir: Path, cfg: dict[str, str]) -> bool:
    updated = False
    now = datetime.now()
    for job in jobs:
        if job.get("status") != "Running":
            continue
        new_status = resolve_status(job, workdir, cfg)
        if new_status == "Running":
            ts = job.get("start_timestamp", time.time())
            job["duration"] = format_duration(time.time() - ts)
            continue
        job["status"] = new_status
        job["end_time"] = now.strftime("%Y-%m-%d %H:%M:%S")
        ts = job.get("start_timestamp", now.timestamp())
        job["duration"] = format_duration(now.timestamp() - ts)
        updated = True
    return updated


def _phase_script_lines(phase: str, workdir: Path, cfg: dict[str, str]) -> list[str]:
    gmx = cfg["gmx"]
    extra = cfg["mdrun_extra"]
    mw = cfg["maxwarn"]
    lines = [
        "#!/usr/bin/env bash",
        "set -o errexit -o nounset -o pipefail",
        f'cd "{workdir}"',
        'echo "=== JOB_START phase=' + phase + ' $(date -Iseconds) ==="',
    ]
    if phase == "em":
        lines += [
            f'{gmx} grompp -f {cfg["em_mdp"]} -c {cfg["solv_ions"]} -p {cfg["top"]} '
            f'-o em.tpr -maxwarn {mw}',
            f'{gmx} mdrun -v -deffnm em {extra}',
        ]
    else:
        run_script = cfg["run_script"]
        if run_script and Path(run_script).exists():
            lines.append(f'bash "{run_script}" {phase} -y')
        else:
            ndx = cfg["ndx"]
            top = cfg["top"]
            if phase == "nvt":
                lines += [
                    f'{gmx} grompp -f nvt.mdp -c {cfg["em_gro"]} -r {cfg["em_gro"]} '
                    f'-p {top} -n {ndx} -o nvt.tpr -maxwarn {mw}',
                    f'{gmx} mdrun -v -deffnm {cfg["nvt_deffnm"]} {extra}',
                ]
            elif phase == "npt":
                nvt = cfg["nvt_deffnm"]
                lines += [
                    f'{gmx} grompp -f npt.mdp -c {nvt}.gro -r {nvt}.gro -t {nvt}.cpt '
                    f'-p {top} -n {ndx} -o npt.tpr -maxwarn {mw}',
                    f'{gmx} mdrun -v -deffnm {cfg["npt_deffnm"]} {extra}',
                ]
            elif phase == "md":
                npt = cfg["npt_deffnm"]
                prod = cfg["prod_deffnm"]
                lines += [
                    f'{gmx} grompp -f md.mdp -c {npt}.gro -t {npt}.cpt '
                    f'-p {top} -n {ndx} -o {prod}.tpr -maxwarn {mw}',
                    f'{gmx} mdrun -v -deffnm {prod} {extra}',
                ]
    lines.append(f'echo "=== JOB_FINISHED {phase} $(date -Iseconds) ==="')
    return lines


def _write_script(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    path.chmod(path.stat().st_mode | 0o111)


def _launcher_with_wait(
    wait_for: str,
    phase_script: Path,
    launcher: Path,
    md_queue_py: Path,
) -> None:
    p = paths()
    cfg = gmx_settings()
    lines = [
        "#!/usr/bin/env bash",
        "set -o errexit -o nounset -o pipefail",
        f'export MDQUEUE_MDPREP_DIR="{p["mdprep"]}"',
        f'export MDQUEUE_WORKDIR="{p["workdir"]}"',
        f'export MDQUEUE_STATE_DIR="{p["state"]}"',
        f'export MDQUEUE_JOBS_FILE="{p["jobs_file"]}"',
        f'export MDQUEUE_LOG_DIR="{p["log_root"]}"',
        f'export MDQUEUE_GMX="{cfg["gmx"]}"',
        f'cd "{p["workdir"]}"',
        f'echo "=== Bekleniyor: {wait_for} ==="',
        f'"{sys.executable}" "{md_queue_py}" wait "{wait_for}"',
        f'exec bash "{phase_script}"',
    ]
    _write_script(launcher, lines)


def submit_phase(
    phase: str,
    wait_for: str | None = None,
    *,
    confirm: bool = True,
) -> int:
    if phase not in PHASES:
        print(f"[!] Bilinmeyen faz: {phase} (em|nvt|npt|md)", file=sys.stderr)
        return 1

    p = paths()
    cfg = gmx_settings()
    workdir = p["workdir"]
    jobs = load_jobs(p["jobs_file"])

    for job in jobs:
        if job.get("phase") == phase and job.get("status") == "Running":
            print(f"[!] {phase.upper()} zaten çalışıyor: {job['job_id']} (PID {job.get('pid')})")
            return 1

    out_file = workdir / expected_output(phase, cfg)
    if out_file.exists():
        ans = "y"
        if confirm:
            ans = input(f"[!] {out_file.name} zaten var — yeniden çalıştır? [y/N] ").strip().lower()
        if ans not in ("y", "yes", "e", "evet"):
            print("İptal.")
            return 0

    if confirm:
        print(f"\n--- Kuyruğa: {phase.upper()} ---")
        print(f"  WORKDIR: {workdir}")
        ans = input("Gönder? [Y/n] ").strip().lower()
        if ans in ("n", "no", "h", "hayir", "hayır"):
            print("İptal.")
            return 0

    job_id = next_job_id(jobs, phase)
    job_dir = p["log_root"] / job_id
    log_file = job_dir / f"{phase}.log"
    phase_script = job_dir / "run.sh"
    _write_script(phase_script, _phase_script_lines(phase, workdir, cfg))

    md_queue_py = Path(__file__).resolve()
    run_target = phase_script
    if wait_for:
        launcher = job_dir / "launcher.sh"
        _launcher_with_wait(wait_for, phase_script, launcher, md_queue_py)
        run_target = launcher

    log_file.parent.mkdir(parents=True, exist_ok=True)
    with log_file.open("w", encoding="utf-8") as logfh:
        proc = subprocess.Popen(
            ["bash", str(run_target)],
            cwd=str(workdir),
            stdout=logfh,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )

    start = datetime.now()
    job = {
        "job_id": job_id,
        "phase": phase,
        "pid": proc.pid,
        "status": "Running",
        "start_time": start.strftime("%Y-%m-%d %H:%M:%S"),
        "start_timestamp": start.timestamp(),
        "end_time": None,
        "duration": None,
        "log_file": str(log_file),
        "wait_for": wait_for,
        "workdir": str(workdir),
    }
    jobs.append(job)
    save_jobs(p["jobs_file"], jobs)

    print(f"[+] Gönderildi: {phase.upper()}  job={job_id}  PID={proc.pid}")
    print(f"    log: {log_file}")
    print(f"    izle: ./md queue status   |   tail -f {log_file}")
    return 0


def submit_chain(*, confirm: bool = True) -> int:
    if confirm:
        print("\nZincir: EM → NVT → NPT → MD (her adım öncekinin bitmesini bekler)")
        ans = input("Tüm zincir kuyruğa gönderilsin mi? [Y/n] ").strip().lower()
        if ans in ("n", "no", "h", "hayir", "hayır"):
            print("İptal.")
            return 0

    wait_for: str | None = None
    last_id = ""
    for phase in PHASES:
        rc = submit_phase(phase, wait_for=wait_for, confirm=False)
        if rc != 0:
            return rc
        jobs = load_jobs(paths()["jobs_file"])
        last_id = jobs[-1]["job_id"]
        wait_for = last_id
    print(f"[+] Zincir gönderildi. Son job: {last_id}")
    return 0


def print_status_table(jobs: list[dict[str, Any]], *, refresh_running: bool = True) -> None:
    p = paths()
    cfg = gmx_settings()
    if refresh_running:
        if refresh_jobs(jobs, p["workdir"], cfg):
            save_jobs(p["jobs_file"], jobs)

    print("\n--- Job Status ---")
    print(f"{'Job':<8}{'Faz':<6}{'Status':<10}{'PID':<8}{'Start':<20}{'Elapsed':<12}Log")
    print("-" * 95)
    if not jobs:
        print("(henüz job yok — ./md queue submit em)")
        return

    for job in jobs:
        if job.get("status") == "Running":
            ts = job.get("start_timestamp", time.time())
            job["duration"] = format_duration(time.time() - ts)
        pid = job.get("pid") or "-"
        log = job.get("log_file", "")
        if log:
            log = Path(log).name
        print(
            f"{job.get('job_id','?'):<8}"
            f"{job.get('phase','?'):<6}"
            f"{job.get('status','?'):<10}"
            f"{str(pid):<8}"
            f"{job.get('start_time','-'):<20}"
            f"{job.get('duration') or '-':<12}"
            f"{log}"
        )


def cmd_summary() -> int:
    """Tek satır özet — ana menü için (bash parse etmez, doğrudan gösterir)."""
    p = paths()
    cfg = gmx_settings()
    jobs = load_jobs(p["jobs_file"])
    refresh_jobs(jobs, p["workdir"], cfg)
    save_jobs(p["jobs_file"], jobs)
    running = [j for j in jobs if j.get("status") == "Running"]
    total = len(jobs)
    if running:
        detail = ", ".join(
            f"{j['job_id']} ({j.get('phase', '?').upper()}, {j.get('duration') or '…'})"
            for j in running
        )
        print(f"{len(running)} çalışıyor — {detail}  (toplam {total} job)")
    elif total == 0:
        print("henüz job yok")
    else:
        last = jobs[-1]
        print(
            f"boşta — son: {last.get('job_id')} "
            f"{last.get('phase', '?').upper()} → {last.get('status')}  (toplam {total})"
        )
    return 0


def recommend_phase(workdir: Path, cfg: dict[str, str]) -> str:
    """Sonraki mantıklı MD fazı."""
    checks = (
        ("em", cfg["em_gro"]),
        ("nvt", f"{cfg['nvt_deffnm']}.gro"),
        ("npt", f"{cfg['npt_deffnm']}.gro"),
        ("md", f"{cfg['prod_deffnm']}.gro"),
    )
    for phase, fname in checks:
        if not (workdir / fname).exists():
            return phase
    return "done"


def cmd_status(watch: bool = False, interval: float = 5.0) -> int:
    p = paths()
    while True:
        jobs = load_jobs(p["jobs_file"])
        print_status_table(jobs)
        running = sum(1 for j in jobs if j.get("status") == "Running")
        print(f"\nÇalışan: {running} / Toplam: {len(jobs)}")
        if not watch:
            break
        if running == 0:
            break
        try:
            time.sleep(interval)
        except KeyboardInterrupt:
            print("\n(izleme durdu)")
            break
        print("\033[2J\033[H", end="")  # clear screen
    return 0


def cmd_wait(job_id: str, timeout: float | None = None) -> int:
    p = paths()
    cfg = gmx_settings()
    start = time.time()
    while True:
        jobs = load_jobs(p["jobs_file"])
        job = next((j for j in jobs if j.get("job_id") == job_id), None)
        if not job:
            print(f"[!] Job bulunamadı: {job_id}", file=sys.stderr)
            return 1
        refresh_jobs(jobs, p["workdir"], cfg)
        save_jobs(p["jobs_file"], jobs)
        st = job.get("status")
        if st == "Finished":
            return 0
        if st in ("Failed", "Aborted", "Crashed"):
            print(f"[!] Önceki job başarısız: {job_id} ({st})", file=sys.stderr)
            return 1
        if timeout and (time.time() - start) > timeout:
            print(f"[!] Zaman aşımı: {job_id}", file=sys.stderr)
            return 1
        time.sleep(15)


def cmd_wait_all(timeout: float | None = None) -> int:
    """Tüm Running job'lar bitene kadar bekle."""
    p = paths()
    cfg = gmx_settings()
    start = time.time()
    for _ in range(120):
        if p["jobs_file"].exists() and load_jobs(p["jobs_file"]):
            break
        time.sleep(1)
    else:
        print("[!] jobs.json boş veya yok — kuyruk gönderilmedi?", file=sys.stderr)
        return 1

    def _active_failures(jobs: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Aynı faz için daha yeni Finished varsa eski Failed yok say."""
        latest: dict[str, dict[str, Any]] = {}
        for job in jobs:
            ph = job.get("phase", "")
            ts = job.get("start_timestamp", 0)
            if ph not in latest or ts >= latest[ph].get("start_timestamp", 0):
                latest[ph] = job
        bad = []
        for ph, job in latest.items():
            if job.get("status") in ("Failed", "Aborted", "Crashed"):
                bad.append(job)
        return bad

    while True:
        jobs = load_jobs(p["jobs_file"])
        if refresh_jobs(jobs, p["workdir"], cfg):
            save_jobs(p["jobs_file"], jobs)
        running = [j for j in jobs if j.get("status") == "Running"]
        failed = _active_failures(jobs)
        if failed and not running:
            j = failed[-1]
            print(
                f"[!] Başarısız job: {j.get('job_id')} ({j.get('status')})",
                file=sys.stderr,
            )
            return 1
        if not running:
            return 0
        if timeout and (time.time() - start) > timeout:
            print("[!] wait-all zaman aşımı", file=sys.stderr)
            return 1
        time.sleep(15)


def cmd_abort(job_id: str) -> int:
    p = paths()
    jobs = load_jobs(p["jobs_file"])
    found = False
    targets = jobs if job_id.lower() == "all" else [j for j in jobs if j.get("job_id") == job_id]

    if not targets and job_id.lower() != "all":
        print(f"[!] Job bulunamadı: {job_id}")
        return 1

    for job in targets:
        if job.get("status") != "Running":
            if job_id.lower() != "all":
                print(f"[i] Çalışmıyor: {job.get('job_id')}")
            continue
        pid = job.get("pid")
        try:
            if pid:
                os.kill(pid, signal.SIGTERM)
            job["status"] = "Aborted"
            job["end_time"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            ts = job.get("start_timestamp", time.time())
            job["duration"] = format_duration(time.time() - ts)
            print(f"[-] İptal: {job.get('job_id')} (PID {pid})")
            found = True
        except OSError as exc:
            print(f"[!] İptal edilemedi {job.get('job_id')}: {exc}")

    if found or job_id.lower() == "all":
        save_jobs(p["jobs_file"], jobs)
    elif not found:
        print("[!] Çalışan eşleşen job yok.")
        return 1
    return 0


def cmd_tail(job_id: str | None = None) -> int:
    p = paths()
    jobs = load_jobs(p["jobs_file"])
    if not jobs:
        print("Job yok.")
        return 1
    if not job_id:
        running = [j for j in jobs if j.get("status") == "Running"]
        job = running[-1] if running else jobs[-1]
    else:
        job = next((j for j in jobs if j.get("job_id") == job_id), None)
        if not job:
            print(f"Job yok: {job_id}")
            return 1
    log = job.get("log_file")
    if not log or not Path(log).exists():
        print(f"Log yok: {log}")
        return 1
    subprocess.run(["tail", "-f", log])
    return 0


def interactive_menu() -> int:
    while True:
        p = paths()
        jobs = load_jobs(p["jobs_file"])
        refresh_jobs(jobs, p["workdir"], gmx_settings())
        save_jobs(p["jobs_file"], jobs)
        running = sum(1 for j in jobs if j.get("status") == "Running")

        print("\n╔══════════════════════════════════════════╗")
        print("║  KUYRUK (yerel iş istasyonu)             ║")
        print("╚══════════════════════════════════════════╝")
        print(f"  WORKDIR: {p['workdir']}")
        print(f"  Çalışan: {running}  |  Toplam: {len(jobs)}  |  kayıt: {p['jobs_file']}")
        print("")
        print("  1) EM gönder")
        print("  2) NVT gönder")
        print("  3) NPT gönder")
        print("  4) MD gönder")
        print("  5) Zincir (EM→NVT→NPT→MD, sıralı)")
        print("  6) Job durumu")
        print("  7) Job iptal")
        print("  8) Tüm job listesi")
        print("  9) Canlı izle (5 sn)")
        print("  t) Log tail (son çalışan)")
        print("  0) Ana menü")
        rec = recommend_phase(p["workdir"], gmx_settings())
        if rec != "done":
            print(f"\n  Öneri: {rec.upper()} gönder (seçenek {PHASES.index(rec)+1})")
        choice = input("Seçim: ").strip().lower()

        if choice == "0":
            return 0
        if choice == "1":
            submit_phase("em")
        elif choice == "2":
            submit_phase("nvt")
        elif choice == "3":
            submit_phase("npt")
        elif choice == "4":
            submit_phase("md")
        elif choice == "5":
            submit_chain()
        elif choice == "6":
            cmd_status()
        elif choice == "7":
            jid = input("Job ID (veya all): ").strip()
            if jid:
                cmd_abort(jid)
        elif choice == "8":
            print_status_table(load_jobs(p["jobs_file"]), refresh_running=False)
        elif choice == "9":
            cmd_status(watch=True)
        elif choice == "t":
            cmd_tail()
        else:
            print("Geçersiz seçim.")
        input("\n↵ ENTER... ")


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    if not argv:
        return interactive_menu()

    cmd = argv[0]
    if cmd in ("menu", "m"):
        return interactive_menu()
    if cmd == "submit" and len(argv) >= 2:
        wait_for = None
        if len(argv) >= 4 and argv[2] in ("--wait-for", "--after"):
            wait_for = argv[3]
        return submit_phase(argv[1], wait_for=wait_for)
    if cmd == "chain":
        return submit_chain()
    if cmd == "summary":
        return cmd_summary()
    if cmd == "recommend":
        p = paths()
        cfg = gmx_settings()
        print(recommend_phase(p["workdir"], cfg))
        return 0
    if cmd in ("status", "list", "st"):
        watch = "--watch" in argv or "-w" in argv
        return cmd_status(watch=watch)
    if cmd in ("abort", "cancel") and len(argv) >= 2:
        return cmd_abort(argv[1])
    if cmd == "wait" and len(argv) >= 2:
        return cmd_wait(argv[1])
    if cmd in ("wait-all", "waitall"):
        return cmd_wait_all()
    if cmd == "tail":
        return cmd_tail(argv[1] if len(argv) >= 2 else None)
    if cmd in ("help", "-h", "--help"):
        print(__doc__)
        print(
            "Komutlar: menu | submit <em|nvt|npt|md> [--wait-for ID] | chain | "
            "status [-w] | summary | recommend | abort ID|all | wait ID | tail [ID]"
        )
        return 0
    print(f"Bilinmeyen: {cmd}. ./md queue help", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
