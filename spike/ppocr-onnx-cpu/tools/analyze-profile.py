import json, sys, glob, collections

for pat in sys.argv[1:]:
    for path in sorted(glob.glob(pat)):
        with open(path, encoding="utf-8") as fh:
            ev = json.load(fh)
        prov = collections.Counter()
        dur = collections.Counter()
        for e in ev:
            args = e.get("args") or {}
            p = args.get("provider")
            if p and e.get("cat") == "Node":
                prov[p] += 1
                dur[p] += e.get("dur", 0)
        total_nodes = sum(prov.values())
        print("==", path)
        if not total_nodes:
            print("   no Node events with provider info")
        for p, c in prov.most_common():
            print("   %-32s nodes=%5d  %5.1f%%  time=%9.0f us" % (p, c, 100.0 * c / total_nodes, dur[p]))
        # per-run session totals
        runs = [e["dur"] for e in ev if e.get("name") == "model_run"]
        if runs:
            runs_sorted = sorted(runs)
            print("   model_run count=%d  median=%.1f ms  first=%.1f ms" %
                  (len(runs), runs_sorted[len(runs) // 2] / 1000.0, runs[0] / 1000.0))
