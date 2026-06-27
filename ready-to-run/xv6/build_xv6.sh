#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
XV6="$ROOT/xv6"
OUT="$ROOT/ready-to-run/xv6"
TOOLS="$ROOT/tools"

pick_toolchain() {
  if [[ -x "$TOOLS/riscv/bin/riscv64-unknown-elf-gcc" ]]; then
    echo "$TOOLS/riscv/bin/riscv64-unknown-elf-"
    return
  fi
  for dir in "$TOOLS"/xpack-riscv-none-elf-gcc-*; do
    if [[ -x "$dir/bin/riscv-none-elf-gcc" ]]; then
      echo "$dir/bin/riscv-none-elf-"
      return
    fi
  done
  if command -v riscv64-unknown-elf-gcc >/dev/null 2>&1; then
    echo "riscv64-unknown-elf-"
    return
  fi
  if command -v riscv64-linux-gnu-gcc >/dev/null 2>&1; then
    echo "riscv64-linux-gnu-"
    return
  fi
  return 1
}

if ! PREFIX="$(pick_toolchain)"; then
  cat <<EOF
No RISC-V toolchain found.

Install one of:
  sudo apt install gcc-riscv64-linux-gnu
  or extract riscv-gnu-toolchain under $TOOLS/riscv/
  or xpack-riscv-none-elf-gcc under $TOOLS/

Then re-run: make build-xv6
EOF
  exit 1
fi

echo "Using TOOLPREFIX=${PREFIX}"
make -C "$XV6" clean
make -C "$XV6" TOOLPREFIX="$PREFIX" kernel/kernel fs.img

mkdir -p "$OUT"
"${PREFIX}objcopy" -O binary "$XV6/kernel/kernel" "$OUT/kernel.bin"
cp "$XV6/fs.img" "$OUT/fs.img"
python3 "$OUT/gen_disk_probe.py"
echo "Built $OUT/kernel.bin ($(wc -c < "$OUT/kernel.bin") bytes) and $OUT/fs.img"
