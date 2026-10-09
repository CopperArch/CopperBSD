#!/usr/bin/env python3.12
"""freebsd-media-setup-with-dash — entry point.

    python3.12 install.py --cli                 # interactive terminal wizard
    python3.12 install.py --cli --profile p.yaml  # reproduce from a profile
    python3.12 install.py --cli --profile p.yaml --dry-run
    python3.12 install.py --cli --profile p.yaml --yes   # no prompts

A tkinter GUI mirrors the Linux edition (py312-tkinter) and calls the same
steps; the CLI is the reliable path over SSH, which is how you'll usually
reproduce a box.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.platform import Platform          # noqa: E402
from lib.profile import Profile            # noqa: E402
from lib.steps import Ctx, ORDER           # noqa: E402
from lib.util import Sudo, log             # noqa: E402


def accept_factory(assume_yes: bool):
    def accept(prompt: str) -> bool:
        if assume_yes:
            log(f"[auto-yes] {prompt}")
            return True
        try:
            return input(f"\n{prompt} [y/N] ").strip().lower() in ("y", "yes")
        except EOFError:
            return False
    return accept


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cli", action="store_true", help="terminal installer")
    ap.add_argument("--profile", type=Path, help="load choices from a YAML profile")
    ap.add_argument("--save-profile", type=Path, help="write the profile back out")
    ap.add_argument("--dry-run", action="store_true", help="show, change nothing")
    ap.add_argument("--yes", action="store_true", help="accept every step")
    args = ap.parse_args()

    plat = Platform.detect()
    log(f"Detected: {plat.pretty}")

    if args.profile and args.profile.exists():
        profile = Profile.from_yaml(args.profile)
        log(f"Loaded profile {args.profile} (your credentials still required)")
    else:
        profile = Profile.with_generated_secrets()
        log("No profile — using defaults + generated secrets "
            "(edit profiles/example.yaml or pass --profile)")

    errs = profile.validate()
    if errs and not args.dry_run:
        for e in errs:
            log(f"  [profile] {e}")
        log("Fix the profile (or --dry-run to preview anyway).")
        return 2

    sudo = Sudo()
    ctx = Ctx(profile, plat, sudo, dry_run=args.dry_run)
    accept = accept_factory(args.yes)

    log("\n=== freebsd-media-setup-with-dash ===")
    failed = []
    for title, step in ORDER:
        log(f"\n--- {title} ---")
        ok, summary = step(ctx, accept)
        log(f"    {'OK ' if ok else 'ERR'}: {summary}")
        if not ok and summary not in ("declined",) and "disabled" not in summary:
            failed.append(title)

    if args.save_profile:
        profile.save(args.save_profile)
        log(f"\nProfile saved to {args.save_profile} (chmod 600)")

    log("\nDone." if not failed else f"\nDone with issues: {', '.join(failed)}")
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
