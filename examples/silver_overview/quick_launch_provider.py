"""Serve the quick-launch catalog; reuse Silver's event and artifact fixture."""
import argparse
import json
from pathlib import Path
import sys

from simulation_fault_provider import main
from simulation_fixture_wire import catalog, sexp


if __name__ == "__main__":
    if "discover" in sys.argv:
        parser = argparse.ArgumentParser()
        parser.add_argument("--control", type=Path, required=True)
        parser.add_argument("--calls", type=Path, required=True)
        parser.add_argument("operation", choices=["discover"])
        parser.add_argument("--protocol-version", choices=["1"], required=True)
        args = parser.parse_args()
        with args.calls.open("a") as out:
            out.write(json.dumps({"operation": "discover"}) + "\n")
        print(sexp(catalog(suite="FIFO", cases=["seeded", "smoke"],
                           parameters=[("n", "10", ["10", "50"])])))
    else:
        main()
