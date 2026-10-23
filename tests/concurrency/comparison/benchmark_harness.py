#!/usr/bin/env python3
import subprocess
import time
import os
import re
import json
import statistics

RUNS = 5

def run_command_measured(cmd):
    start = time.perf_counter()
    # Use /usr/bin/time -v to collect detailed kernel-level stats
    proc = subprocess.run(["/usr/bin/time", "-v"] + cmd,
                          stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE,
                          text=True)
    elapsed = time.perf_counter() - start
    
    # Parse /usr/bin/time -v output from stderr
    stderr = proc.stderr
    max_rss = 0
    user_time = 0.0
    sys_time = 0.0
    vol_cs = 0
    invol_cs = 0
    
    for line in stderr.splitlines():
        line = line.strip()
        if "Maximum resident set size (kbytes):" in line:
            max_rss = int(line.split(":")[-1].strip())
        elif "User time (seconds):" in line:
            user_time = float(line.split(":")[-1].strip())
        elif "System time (seconds):" in line:
            sys_time = float(line.split(":")[-1].strip())
        elif "Voluntary context switches:" in line:
            vol_cs = int(line.split(":")[-1].strip())
        elif "Involuntary context switches:" in line:
            invol_cs = int(line.split(":")[-1].strip())

    category_times = parse_categories(proc.stdout)

    return {
        "wall_time_sec": elapsed,
        "user_time_sec": user_time,
        "sys_time_sec": sys_time,
        "cpu_percent": round((user_time + sys_time) / elapsed * 100, 1) if elapsed > 0 else 0,
        "max_rss_kb": max_rss,
        "max_rss_mb": round(max_rss / 1024.0, 2),
        "vol_context_switches": vol_cs,
        "invol_context_switches": invol_cs,
        "exit_code": proc.returncode,
        "category_times": category_times,
        "stdout": proc.stdout
    }

def parse_categories(stdout_text):
    categories = {}
    current_cat = None
    # Looking for:
    # --- [Category] 1. Deep Recursion & Call-Chaining (50 tests) ---
    #     Result: 50/50 passed (0 failed) in 15 ms
    for line in stdout_text.splitlines():
        cat_match = re.search(r"---\s*\[Category\]\s*(\d+)\.\s*([^(]+)", line)
        if cat_match:
            cat_id = int(cat_match.group(1))
            cat_name = cat_match.group(2).strip()
            current_cat = (cat_id, cat_name)
        elif current_cat:
            res_match = re.search(r"Result:\s*(\d+)/(\d+)\s*passed\s*\((\d+)\s*failed\)\s*in\s*(\d+)\s*ms", line)
            if res_match:
                cat_id, cat_name = current_cat
                categories[str(cat_id)] = {
                    "id": cat_id,
                    "name": cat_name,
                    "passed": int(res_match.group(1)),
                    "total": int(res_match.group(2)),
                    "failed": int(res_match.group(3)),
                    "elapsed_ms": int(res_match.group(4))
                }
                current_cat = None
    return categories

def count_lines(filepath):
    if not os.path.exists(filepath):
        return 0
    with open(filepath, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip() and not line.strip().startswith("//") and not line.strip().startswith("{")]
        return len(lines)

def get_binary_size(filepath):
    if os.path.exists(filepath):
        return os.path.getsize(filepath)
    return 0

print("===================================================================")
print("BENCHMARKING 1000 ASYNC/AWAIT STRESS TESTS: MFPC PASCAL vs C# .NET 8")
print(f"Executing {RUNS} iterations for statistical averaging...")
print("===================================================================")

pascal_bin = "./tests/concurrency/comparison/stress_1000_tests"
csharp_cmd = ["dotnet", "./tests/concurrency/comparison/csharp_stress/bin/Release/net8.0/Stress500.dll"]

pascal_runs = []
print("\n>>> Running MFPC Pascal (5 iterations)...")
for i in range(RUNS):
    res = run_command_measured([pascal_bin])
    pascal_runs.append(res)
    print(f"  Run {i+1}: Wall {res['wall_time_sec']*1000:.1f} ms | Max RSS {res['max_rss_mb']} MB | CPU {res['cpu_percent']}% | Vol CS {res['vol_context_switches']}")

csharp_runs = []
print("\n>>> Running C# .NET 8 (5 iterations)...")
for i in range(RUNS):
    res = run_command_measured(csharp_cmd)
    csharp_runs.append(res)
    print(f"  Run {i+1}: Wall {res['wall_time_sec']*1000:.1f} ms | Max RSS {res['max_rss_mb']} MB | CPU {res['cpu_percent']}% | Vol CS {res['vol_context_switches']}")

def summarize(runs):
    walls = [r["wall_time_sec"] for r in runs]
    rss = [r["max_rss_mb"] for r in runs]
    users = [r["user_time_sec"] for r in runs]
    syss = [r["sys_time_sec"] for r in runs]
    vol = [r["vol_context_switches"] for r in runs]
    invol = [r["invol_context_switches"] for r in runs]
    
    # Average category times across runs
    cat_avg = {}
    if runs and "category_times" in runs[0]:
        for cat_key in runs[0]["category_times"].keys():
            times = [r["category_times"][cat_key]["elapsed_ms"] for r in runs if cat_key in r["category_times"]]
            name = runs[0]["category_times"][cat_key]["name"]
            passed = runs[0]["category_times"][cat_key]["passed"]
            total = runs[0]["category_times"][cat_key]["total"]
            failed = runs[0]["category_times"][cat_key]["failed"]
            cat_avg[cat_key] = {
                "id": int(cat_key),
                "name": name,
                "passed": passed,
                "total": total,
                "failed": failed,
                "avg_ms": round(statistics.mean(times), 1) if times else 0,
                "min_ms": min(times) if times else 0,
                "max_ms": max(times) if times else 0
            }

    return {
        "wall_avg": statistics.mean(walls),
        "wall_min": min(walls),
        "wall_max": max(walls),
        "wall_stdev": statistics.stdev(walls) if len(walls) > 1 else 0,
        "rss_avg": statistics.mean(rss),
        "rss_min": min(rss),
        "rss_max": max(rss),
        "user_avg": statistics.mean(users),
        "sys_avg": statistics.mean(syss),
        "vol_cs_avg": statistics.mean(vol),
        "invol_cs_avg": statistics.mean(invol),
        "categories": cat_avg
    }

pas_summary = summarize(pascal_runs)
cs_summary = summarize(csharp_runs)

pas_loc = count_lines("tests/concurrency/comparison/stress_1000_tests.pp")
cs_loc = count_lines("tests/concurrency/comparison/csharp_stress/Program.cs")
pas_size = get_binary_size(pascal_bin)
cs_dll_size = get_binary_size("tests/concurrency/comparison/csharp_stress/bin/Release/net8.0/Stress500.dll")

summary_data = {
    "pascal": {
        "summary": pas_summary,
        "loc": pas_loc,
        "binary_bytes": pas_size,
        "binary_mb": round(pas_size / (1024 * 1024), 2),
        "raw_runs": [{k: v for k, v in r.items() if k != "stdout"} for r in pascal_runs]
    },
    "csharp": {
        "summary": cs_summary,
        "loc": cs_loc,
        "binary_bytes": cs_dll_size,
        "binary_mb": round(cs_dll_size / (1024 * 1024), 2),
        "raw_runs": [{k: v for k, v in r.items() if k != "stdout"} for r in csharp_runs]
    }
}

with open("tests/concurrency/comparison/benchmark_1000_results.json", "w") as f:
    json.dump(summary_data, f, indent=2)

print("\n===================================================================")
print("                   1000 TESTS COMPARISON SUMMARY                   ")
print("===================================================================")
print(f"{'Metric':<35} | {'MFPC (Pascal)':<18} | {'C# (.NET 8)':<18} | {'Delta / Advantage':<20}")
print("-" * 100)
print(f"{'Wall Time (Avg, 5 runs)':<35} | {pas_summary['wall_avg']*1000:>15.1f} ms | {cs_summary['wall_avg']*1000:>15.1f} ms | {pas_summary['wall_avg']/cs_summary['wall_avg']:>18.2f}x")
print(f"{'Wall Time (Min / Fastest)':<35} | {pas_summary['wall_min']*1000:>15.1f} ms | {cs_summary['wall_min']*1000:>15.1f} ms | {pas_summary['wall_min']/cs_summary['wall_min']:>18.2f}x")
print(f"{'Wall Time StDev':<35} | {pas_summary['wall_stdev']*1000:>15.2f} ms | {cs_summary['wall_stdev']*1000:>15.2f} ms | {'-':>18}")
print(f"{'Peak RSS Memory':<35} | {pas_summary['rss_avg']:>15.2f} MB | {cs_summary['rss_avg']:>15.2f} MB | {cs_summary['rss_avg']/pas_summary['rss_avg']:>17.2f}x less RAM")
print(f"{'User CPU Time':<35} | {pas_summary['user_avg']:>15.3f} s  | {cs_summary['user_avg']:>15.3f} s  | {pas_summary['user_avg']/cs_summary['user_avg']:>18.2f}x")
print(f"{'System / Kernel Time':<35} | {pas_summary['sys_avg']:>15.3f} s  | {cs_summary['sys_avg']:>15.3f} s  | {cs_summary['sys_avg']/pas_summary['sys_avg']:>17.2f}x")
print(f"{'Voluntary Context Switches':<35} | {pas_summary['vol_cs_avg']:>15.0f}    | {cs_summary['vol_cs_avg']:>15.0f}    | {cs_summary['vol_cs_avg']/pas_summary['vol_cs_avg']:>18.2f}x")
print(f"{'Involuntary Context Switches':<35} | {pas_summary['invol_cs_avg']:>15.0f}    | {cs_summary['invol_cs_avg']:>15.0f}    | {cs_summary['invol_cs_avg']/pas_summary['invol_cs_avg']:>18.2f}x")
print(f"{'Executable Binary Size':<35} | {summary_data['pascal']['binary_mb']:>15.2f} MB | {summary_data['csharp']['binary_mb']:>15.2f} MB (+Runtime)| Standalone native")
print(f"{'Effective Lines of Code (LOC)':<35} | {pas_loc:>15} lines | {cs_loc:>15} lines | {pas_loc/cs_loc:>18.2f}x")
print("===================================================================")

print("\n--- CATEGORY BREAKDOWN (AVG OF 5 RUNS) ---")
print(f"{'Cat #':<6} | {'Category Name':<42} | {'MFPC (ms)':<10} | {'C# (ms)':<10} | {'Ratio':<10}")
print("-" * 85)
for i in range(1, 21):
    k = str(i)
    p_info = pas_summary['categories'].get(k, {})
    c_info = cs_summary['categories'].get(k, {})
    p_time = p_info.get('avg_ms', 0)
    c_time = c_info.get('avg_ms', 0)
    name = p_info.get('name', c_info.get('name', f"Category {i}"))
    ratio_str = f"{p_time/c_time:.2f}x" if c_time > 0 else "N/A"
    print(f"{i:<6} | {name[:42]:<42} | {p_time:>8.1f} ms | {c_time:>8.1f} ms | {ratio_str:>10}")
print("===================================================================")
