#!/usr/bin/env python3
"""DEPRECATED -- use scripts/cov_report.py instead.

This was the first ad-hoc .vdb reader. It counted characters in the raw
`value` attribute of every metric, which is only valid for the bit-string
metrics: for `assert` the attribute holds space-separated integer tuples, and
its covergroup parsing never matched anything (bins live in <cg_covdef>, not in
<cg_src>), so it silently reported no functional coverage. Both of those
numbers were wrong; cov_report.py replaces them.

Kept as a thin forwarder so old muscle memory keeps working.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TARGET = os.path.join(HERE, "cov_report.py")

if __name__ == "__main__":
    sys.stderr.write(
        "note: scripts/parse_cov.py is deprecated, forwarding to "
        "scripts/cov_report.py\n"
    )
    args = list(sys.argv[1:])
    if not any(a in ("-dir", "--dir") for a in args):
        if args and not args[0].startswith("-"):
            args = ["-dir", args.pop(0)] + args
        else:
            args = ["-dir", "sim/build/core_vcs/simv.vdb"] + args
    os.execv(sys.executable, [sys.executable, TARGET] + args)
