#!/usr/bin/env python3
"""
Sync terraform.tfvars to .env file.

Reads variables from terraform.tfvars and writes them to .env file
with appropriate formatting for use in shell scripts and applications.
"""

import argparse
import sys
from pathlib import Path
from typing import Any


def parse_tfvars(tfvars_file: Path) -> dict[str, Any]:
    """
    Parse terraform.tfvars file manually.

    We use a simple parser instead of hcl2 to avoid external dependencies.
    This handles the most common tfvars patterns.
    """
    variables = {}

    try:
        with tfvars_file.open() as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"Error: {tfvars_file} not found", file=sys.stderr)
        sys.exit(1)

    i = 0
    while i < len(lines):
        line = lines[i].strip()

        # Skip comments and empty lines
        if not line or line.startswith("#") or line.startswith("//"):
            i += 1
            continue

        # Handle variable assignments
        if "=" in line:
            # Split on first =
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip()

            # Remove trailing comment
            if "#" in value:
                value = value.split("#")[0].strip()

            # Handle multi-line values (lists, maps)
            if value.endswith("{") or value.endswith("["):
                # Collect multi-line value
                multi_value = [value]
                i += 1
                bracket_count = value.count("{") + value.count("[")
                bracket_count -= value.count("}") + value.count("]")

                while i < len(lines) and bracket_count > 0:
                    next_line = lines[i].strip()
                    if next_line and not next_line.startswith("#"):
                        multi_value.append(next_line)
                        bracket_count += next_line.count("{") + next_line.count("[")
                        bracket_count -= next_line.count("}") + next_line.count("]")
                    i += 1

                value = " ".join(multi_value)

            # Parse the value
            variables[key] = parse_value(value)

        i += 1

    return variables


def parse_value(value: str) -> Any:
    """Parse a Terraform value to Python type."""
    value = value.strip()

    # Remove trailing comma if present
    if value.endswith(","):
        value = value[:-1].strip()

    # Boolean values
    if value.lower() == "true":
        return True
    if value.lower() == "false":
        return False

    # Null values
    if value.lower() == "null":
        return None

    # String values (quoted)
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]

    # Number values
    try:
        if "." in value:
            return float(value)
        return int(value)
    except ValueError:
        pass

    # List values
    if value.startswith("[") and value.endswith("]"):
        # Simple list parsing
        inner = value[1:-1].strip()
        if not inner:
            return []

        items = []
        for item in inner.split(","):
            item = item.strip()
            if item:
                items.append(parse_value(item))
        return items

    # Map/object values - return as JSON-like string
    if value.startswith("{") and value.endswith("}"):
        return value

    # Default: return as string
    return value


def format_env_value(value: Any) -> str:
    """Format a Python value for .env file."""
    if value is None:
        return ""

    if isinstance(value, bool):
        return "true" if value else "false"

    if isinstance(value, (int, float)):
        return str(value)

    if isinstance(value, list):
        # Join list items with commas
        return ",".join(str(v) for v in value)

    if isinstance(value, dict):
        # For complex objects, return as JSON
        import json

        return json.dumps(value)

    # String value - quote if contains spaces or special chars
    str_value = str(value)
    if " " in str_value or any(c in str_value for c in ["$", '"', "'", "`", "\\"]):
        # Escape quotes and backslashes
        escaped = str_value.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'

    return str_value


def read_env_file(env_file: Path) -> dict[str, str]:
    """Read existing .env file."""
    env_vars = {}

    if not env_file.exists():
        return env_vars

    with env_file.open() as f:
        for line in f:
            line = line.strip()

            # Skip comments and empty lines
            if not line or line.startswith("#"):
                continue

            # Handle KEY=VALUE format
            if "=" in line:
                key, _, value = line.partition("=")
                key = key.strip()
                value = value.strip()

                # Remove quotes if present
                if (value.startswith('"') and value.endswith('"')) or (
                    value.startswith("'") and value.endswith("'")
                ):
                    value = value[1:-1]

                env_vars[key] = value

    return env_vars


def write_env_file(env_file: Path, variables: dict[str, str], header: str | None = None) -> None:
    """Write variables to .env file."""
    with env_file.open("w") as f:
        # Write header
        if header:
            f.write(header)
            f.write("\n\n")

        # Write variables in sorted order
        for key in sorted(variables.keys()):
            value = variables[key]
            f.write(f"{key}={value}\n")


def sync_tfvars_to_env(
    tfvars_file: Path,
    env_file: Path,
    prefix: str = "",
    overwrite: bool = False,
) -> None:
    """
    Sync terraform.tfvars to .env file.

    Args:
        tfvars_file: Path to terraform.tfvars
        env_file: Path to .env file
        prefix: Prefix to add to variable names (default: none)
        overwrite: If True, overwrite existing .env; if False, merge
    """
    # Parse tfvars
    print(f"📖 Reading {tfvars_file}...")
    tfvars = parse_tfvars(tfvars_file)
    print(f"   Found {len(tfvars)} variables")

    # Read existing .env if not overwriting
    env_vars = {} if overwrite else read_env_file(env_file)

    # Convert tfvars to env format
    updated_count = 0
    new_count = 0

    for key, value in tfvars.items():
        env_key = f"{prefix}{key.upper()}"
        env_value = format_env_value(value)

        if env_key in env_vars:
            if env_vars[env_key] != env_value:
                updated_count += 1
        else:
            new_count += 1

        env_vars[env_key] = env_value

    # Generate header
    header = f"""# Environment variables synced from {tfvars_file.name}
# Generated by sync-tfvars-to-env.py
# DO NOT EDIT THIS FILE MANUALLY - Changes will be overwritten
#
# To update: make sync-env or run scripts/sync-tfvars-to-env.py"""

    # Write .env file
    print(f"✍️  Writing {env_file}...")
    write_env_file(env_file, env_vars, header)

    # Summary
    print("✅ Sync complete!")
    print(f"   - New variables: {new_count}")
    print(f"   - Updated variables: {updated_count}")
    print(f"   - Total variables in .env: {len(env_vars)}")


def main() -> None:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Sync terraform.tfvars to .env file",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Sync bootstrap terraform.tfvars to .env (no prefix by default)
  %(prog)s

  # Sync with custom files
  %(prog)s --tfvars custom.tfvars --env custom.env

  # Add TF_VAR_ prefix (for Terraform input variables)
  %(prog)s --tf-var-prefix

  # Custom prefix
  %(prog)s --prefix "APP_"

  # Overwrite .env completely (default: merge with existing)
  %(prog)s --overwrite
        """,
    )

    parser.add_argument(
        "--tfvars",
        type=Path,
        default=Path("bootstrap/terraform.tfvars"),
        help="Path to terraform.tfvars file (default: bootstrap/terraform.tfvars)",
    )

    parser.add_argument(
        "--env",
        type=Path,
        default=Path(".env"),
        help="Path to .env file (default: .env)",
    )

    parser.add_argument(
        "--prefix",
        type=str,
        default="",
        help="Prefix for environment variables (default: none)",
    )

    parser.add_argument(
        "--tf-var-prefix",
        action="store_true",
        help="Add TF_VAR_ prefix (for Terraform input variables)",
    )

    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite .env file completely (default: merge with existing)",
    )

    args = parser.parse_args()

    # Handle --tf-var-prefix flag
    prefix = "TF_VAR_" if args.tf_var_prefix else args.prefix

    # Run sync
    try:
        sync_tfvars_to_env(
            tfvars_file=args.tfvars,
            env_file=args.env,
            prefix=prefix,
            overwrite=args.overwrite,
        )
    except Exception as e:
        print(f"❌ Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
