import subprocess
from pathlib import Path
import sys

# Configuration
CPU = "cortex-a72"
ARCH = "armv8-a"

def compile_and_link():
    SRC_DIR = Path("./")
    BUILD_DIR = SRC_DIR / "build"
    BUILD_DIR.mkdir(exist_ok=True)
    OUTPUT_EXE = SRC_DIR / "aft_firmware"

    print(f"[INFO] Scanning recursively for .c and .S/.s files in {SRC_DIR}")

    # Find all .c, .S, and .s files
    source_files = [p for p in SRC_DIR.rglob("*") if p.suffix.lower() in [".c", ".s", ".S"]]

    if not source_files:
        print("[ERROR] No source files found! Check your path.")
        sys.exit(1)

    obj_files = []

    for src_file in source_files:
        obj_file = BUILD_DIR / (src_file.stem + ".o")
        print(f"[INFO] Compiling {src_file} -> {obj_file}")

        # Use gcc for both C and assembly files to ensure correct flags
        compile_cmd = [
            "gcc",
            "-c",
            "-ffreestanding",
            f"-mcpu={CPU}",
            f"-march={ARCH}",
            str(src_file),
            "-o",
            str(obj_file)
        ]

        try:
            subprocess.run(compile_cmd, check=True)
        except subprocess.CalledProcessError as e:
            print(f"[ERROR] Compilation failed for {src_file}")
            sys.exit(1)

        obj_files.append(obj_file)

    # Use custom linker script if available
    linker_script = SRC_DIR / "linker.ld"
    linker_args = []
    if linker_script.exists():
        print(f"[INFO] Using linker script: {linker_script}")
        linker_args = ["-T", str(linker_script)]
    else:
        print("[WARNING] No linker script found. ELF may not have correct memory layout or entry point.")

    # Link everything into a freestanding ELF
    print(f"[INFO] Linking {len(obj_files)} object files into {OUTPUT_EXE}")
    link_cmd = [
        "gcc",
        *map(str, obj_files),
        *linker_args,
        "-nostartfiles",
        "-nodefaultlibs",
        "-static",
        "-ffreestanding",
        "-o",
        str(OUTPUT_EXE)
    ]

    try:
        subprocess.run(link_cmd, check=True)
    except subprocess.CalledProcessError:
        print("[ERROR] Linking failed.")
        sys.exit(1)

    print(f"[SUCCESS] Build complete. Freestanding ELF created at: {OUTPUT_EXE}")

if __name__ == "__main__":
    compile_and_link()