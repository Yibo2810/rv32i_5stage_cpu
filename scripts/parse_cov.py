#!/usr/bin/env python3

import gzip, re, os, sys

vdb = sys.argv[1] if len(sys.argv) > 1 else "sim/build/core_vcs/simv.vdb"
testdata = os.path.join(vdb, "snps/coverage/db/testdata/test")

if not os.path.isdir(testdata):
    print(f"ERROR: {testdata} not found. 先跑 make cov。")
    sys.exit(1)

metrics = {}

for fname in ["line.verilog.data.xml", "branch.verilog.data.xml",
              "cond.verilog.data.xml", "tgl.verilog.data.xml",
              "fsm.verilog.data.xml", "assert.verilog.data.xml"]:
    path = os.path.join(testdata, fname)
    if not os.path.exists(path):
        continue
    content = gzip.open(path).read().decode("utf-8", errors="replace")
    metric = fname.split(".")[0]
    instances = re.findall(
        r'<instance_data name="([^"]+)"\s+value="([^"]*)"', content
    )
    for name, value in instances:
        total = len(value)
        hit = value.count("1")
        pct = 100.0 * hit / total if total > 0 else 0
        metrics[f"{metric}:{name}"] = (hit, total, pct)

func_holes = []
cum_path = os.path.join(testdata, "testbench.cumulative.xml")
if os.path.exists(cum_path):
    content = gzip.open(cum_path).read().decode("utf-8", errors="replace")
    for cg in re.finditer(
        r'<cg_src\s+[^>]*name="([^"]+)"[^>]*>(.*?)</cg_src\s*>',
        content, re.DOTALL,
    ):
        cg_name, body = cg.group(1), cg.group(2)
        cp_names = dict(re.findall(r'<cp\s+id="(\d+)"\s+exprname="([^"]+)"', body))
        for cp in re.finditer(
            r'<cp\s+type="user"\s+id="(\d+)"[^>]*>(.*?)</cp\s*>',
            body, re.DOTALL,
        ):
            cp_name = cp_names.get(cp.group(1), f"cp{cp.group(1)}")
            hit, total = 0, 0
            for bn in re.finditer(
                r'<bn\s+[^>]*name="([^"]*)"\s+data="(\d+)"'
                r'(?:\s+excl="(\d)")?(?:\s+illegal="(\d)")?',
                cp.group(2),
            ):
                bname, data, excl, illegal = bn.groups()
                if excl == "1" or illegal == "1":
                    continue
                total += 1
                if int(data) > 0:
                    hit += 1
                else:
                    func_holes.append(f"{cg_name}.{cp_name}.{bname}")
            if total > 0:
                metrics[f"func:{cg_name}.{cp_name}"] = (
                    hit, total, 100.0 * hit / total
                )

print("=" * 60)
print("COVERAGE SUMMARY")
print("=" * 60)

for metric_name in ["line", "branch", "cond", "tgl", "fsm", "assert"]:
    print(f"\n--- {metric_name.upper()} ---")
    for key, (hit, total, pct) in sorted(metrics.items()):
        if key.startswith(f"{metric_name}:") and total > 0:
            inst = key.split(":", 1)[1].replace("core_sv_tb.", "")
            pct_str = f"{pct:.1f}%" if pct is not None else "N/A"
            bar = (
                "█" * int(pct / 5) + "░" * (20 - int(pct / 5))
                if pct is not None and pct > 0
                else ""
            )
            print(f"  {inst:35s} {hit:4d}/{total:<4d} {pct_str:>6s} {bar}")

print(f"\n--- FUNCTIONAL ---")
for key, (hit, total, pct) in sorted(metrics.items()):
    if key.startswith("func:"):
        inst = key.split(":", 1)[1]
        bar = "█" * int(pct / 5) + "░" * (20 - int(pct / 5))
        print(f"  {inst:35s} {hit:4d}/{total:<4d} {pct:>5.1f}% {bar}")

print(f"\n{'='*60}")
print("OVERALL:")
for mn in ["line", "branch", "cond", "tgl"]:
    agg_hit = sum(
        v[0]
        for k, v in metrics.items()
        if k.startswith(f"{mn}:") and v[1] > 0
    )
    agg_tot = sum(
        v[1]
        for k, v in metrics.items()
        if k.startswith(f"{mn}:") and v[1] > 0
    )
    if agg_tot > 0:
        print(f"  {mn:8s}: {agg_hit}/{agg_tot} ({100.0*agg_hit/agg_tot:.1f}%)")

print(f"\n--- HOLES (line & branch < 100%) ---")
for key, (hit, total, pct) in sorted(metrics.items()):
    if (key.startswith("line:") or key.startswith("branch:")) \
       and hit < total and total > 0:
        mn, inst = key.split(":", 1)
        print(f"  [{mn}] {inst}: {hit}/{total} ({pct:.1f}%)")

print(f"\n--- FUNCTIONAL HOLES (zero-hit bins) ---")
for h in func_holes:
    print(f"  [func] {h} : 0 hits")
