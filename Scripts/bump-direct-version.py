#!/usr/bin/env python3
"""Advance the shared release version and its app-identity test expectations."""

import argparse
import os
from pathlib import Path
import re
import stat
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = Path("Configuration/Shared.xcconfig")
IDENTITY_PATH = Path("SystemHeadroomTests/AppIdentityTests.swift")


def _single_match(pattern, text, label):
    matches = list(re.finditer(pattern, text, re.MULTILINE))
    if len(matches) != 1:
        raise ValueError(f"expected exactly one {label}; found {len(matches)}")
    return matches[0]


def _setting(text, name):
    return _single_match(
        rf"^[ \t]*{name}[ \t]*=[ \t]*(?P<value>[^\r\n]*?)[ \t]*(?=\r?$)",
        text,
        f"{name} assignment",
    )


def _pin(text, name):
    return _single_match(
        rf'^[ \t]*#expect\({name} == "(?P<value>[^"\r\n]*)"\)[ \t]*(?=\r?$)',
        text,
        f'#expect({name} == "...") test pin',
    )


def _version_tuple(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value):
        raise ValueError("marketing version must contain one to three numeric components")
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def _build_number(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]+", value) or int(value) <= 0:
        raise ValueError("build number must be a positive integer")
    return int(value)


def _replace_values(text, replacements):
    # Work backwards so changing a value's length cannot move another match.
    for match, value in sorted(replacements, key=lambda item: item[0].start(), reverse=True):
        start, end = match.span("value")
        text = text[:start] + value + text[end:]
    return text


def plan_version_bump(config_text, identity_text, version=None, build=None):
    """Validate current contents and return proposed contents without touching files."""
    marketing = _setting(config_text, "MARKETING_VERSION")
    current_build = _setting(config_text, "CURRENT_PROJECT_VERSION")
    short_pin = _pin(identity_text, "short")
    build_pin = _pin(identity_text, "build")
    old_version = marketing.group("value")
    old_build = current_build.group("value")
    old_version_tuple = _version_tuple(old_version)
    old_build_number = _build_number(old_build)
    if short_pin.group("value") != old_version or build_pin.group("value") != old_build:
        raise ValueError("app-identity test pins must match the current shared version and build")

    new_version = old_version if version is None else version
    if _version_tuple(new_version) < old_version_tuple:
        raise ValueError("marketing version must not decrease")
    new_build_number = old_build_number + 1 if build is None else _build_number(build)
    if new_build_number <= old_build_number:
        raise ValueError(f"build number must exceed the current build ({old_build})")
    new_build = str(new_build_number)
    return {
        "version": new_version,
        "build": new_build,
        "config": _replace_values(config_text, [(marketing, new_version), (current_build, new_build)]),
        "identity_tests": _replace_values(identity_text, [(short_pin, new_version), (build_pin, new_build)]),
    }


def _stage_file(path, contents, mode):
    descriptor, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(contents)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.chmod(mode)
        return temporary
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def bump_files(root=ROOT, version=None, build=None):
    """Validate both files before writing, preserving unrelated bytes and file modes."""
    paths = [Path(root) / CONFIG_PATH, Path(root) / IDENTITY_PATH]
    originals = [path.read_bytes() for path in paths]
    modes = [stat.S_IMODE(path.stat().st_mode) for path in paths]
    plan = plan_version_bump(*(contents.decode("utf-8") for contents in originals), version=version, build=build)
    updated = [plan["config"].encode("utf-8"), plan["identity_tests"].encode("utf-8")]
    staged = []
    replaced = []
    try:
        # Prepare both replacements before either source file changes.
        for path, contents, mode in zip(paths, updated, modes):
            staged.append(_stage_file(path, contents, mode))
        if any(path.read_bytes() != original for path, original in zip(paths, originals)):
            raise ValueError("release identity files changed while preparing the version bump; retry")
        for index, (path, temporary) in enumerate(zip(paths, staged)):
            os.replace(temporary, path)
            replaced.append(index)
    except BaseException:
        # Restore any completed replacement if the second replacement fails.
        for index in reversed(replaced):
            restore = _stage_file(paths[index], originals[index], modes[index])
            try:
                os.replace(restore, paths[index])
            finally:
                restore.unlink(missing_ok=True)
        raise
    finally:
        for temporary in staged:
            temporary.unlink(missing_ok=True)
    return plan


def main(argv=None, root=ROOT):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="marketing version, such as 1.2 or 1.2.3; defaults to unchanged")
    parser.add_argument("--build", help="positive build number above the current value; defaults to current + 1")
    arguments = parser.parse_args(argv)
    plan = bump_files(root, version=arguments.version, build=arguments.build)
    print(f"Release version: {plan['version']} ({plan['build']})")
    print(f"Updated: {CONFIG_PATH}")
    print(f"Updated: {IDENTITY_PATH}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as error:
        sys.exit(f"FAIL: {error}")
