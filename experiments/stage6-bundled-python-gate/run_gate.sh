#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

experiment_dir="${0:A:h}"
source_python_root="/Library/Frameworks/Python.framework/Versions/3.13"
temporary_root="$(mktemp -d /tmp/stage6-bundled-python-gate.XXXXXX)"
trap 'rm -rf -- "$temporary_root"' EXIT

app_contents="$temporary_root/Stage6BundledPythonGate.app/Contents"
framework_version="$app_contents/Frameworks/Python.framework/Versions/3.13"
swift_executable="$app_contents/MacOS/Stage6BundledPythonGate"
fixture_destination="$app_contents/Resources/Stage6/stage6_gate_fixture.py"
inner_python_app="$framework_version/Resources/Python.app"
inner_python_executable="$inner_python_app/Contents/MacOS/Python"

actual_version="$($source_python_root/bin/python3 -I -S --version 2>&1)"
if [[ "$actual_version" != "Python 3.13.14" ]]; then
    print -u2 -- "unexpected source Python: $actual_version"
    exit 10
fi

mkdir -p "$app_contents/MacOS" "$framework_version/bin" "$framework_version/lib" "$framework_version/Resources" "$inner_python_app/Contents/MacOS" "${fixture_destination:h}"
/usr/bin/swiftc -module-cache-path "$temporary_root/module-cache" "$experiment_dir/Sources/main.swift" -o "$swift_executable"
/bin/cp "$source_python_root/bin/python3.13" "$framework_version/bin/python3.13"
/bin/cp "$source_python_root/Python" "$framework_version/Python"
/bin/cp "$source_python_root/Resources/Info.plist" "$framework_version/Resources/Info.plist"
/bin/cp "$source_python_root/Resources/Python.app/Contents/MacOS/Python" "$inner_python_executable"
/bin/cp "$source_python_root/Resources/Python.app/Contents/Info.plist" "$inner_python_app/Contents/Info.plist"
/usr/bin/rsync -a --exclude site-packages --exclude ensurepip --exclude '*.whl' --exclude '*.dist-info' --exclude '*.egg-info' --exclude __pycache__ "$source_python_root/lib/python3.13/" "$framework_version/lib/python3.13/"
/bin/cp "$experiment_dir/python/stage6_gate_fixture.py" "$fixture_destination"
/bin/cp "$experiment_dir/Info.plist" "$app_contents/Info.plist"
/bin/ln -s 3.13 "$app_contents/Frameworks/Python.framework/Versions/Current"
/bin/ln -s Versions/Current/Python "$app_contents/Frameworks/Python.framework/Python"
/bin/ln -s Versions/Current/Resources "$app_contents/Frameworks/Python.framework/Resources"

/usr/bin/install_name_tool -change "$source_python_root/Python" "@executable_path/../Python" "$framework_version/bin/python3.13"
/usr/bin/install_name_tool -change "$source_python_root/Python" "@executable_path/../../../../Python" "$inner_python_executable"
/usr/bin/install_name_tool -id "@rpath/Python.framework/Versions/3.13/Python" "$framework_version/Python"
/usr/bin/codesign --force --sign - "$framework_version/Python"
/usr/bin/codesign --force --sign - "$framework_version/bin/python3.13"
/usr/bin/codesign --force --sign - "$inner_python_executable"
/usr/bin/codesign --force --sign - "$inner_python_app"
/usr/bin/codesign --force --sign - "$app_contents/Frameworks/Python.framework"
/usr/bin/codesign --force --sign - "$swift_executable"
/usr/bin/codesign --force --sign - "$temporary_root/Stage6BundledPythonGate.app"

if /usr/bin/otool -L "$framework_version/bin/python3.13" | /usr/bin/grep -F "$source_python_root" >/dev/null; then
    print -u2 -- "bundled executable retains source framework dependency"
    exit 11
fi
if /usr/bin/otool -L "$inner_python_executable" | /usr/bin/grep -F "$source_python_root" >/dev/null; then
    print -u2 -- "bundled interpreter retains source framework dependency"
    exit 11
fi

if [[ -n "$(/usr/bin/find "$framework_version/lib/python3.13" \( -name site-packages -o -name '*.whl' -o -name '*.dist-info' -o -name '*.egg-info' \) -print -quit)" ]]; then
    print -u2 -- "third-party package material found in bundled stdlib"
    exit 12
fi

if /usr/bin/grep -E 'URLSession|NWConnection|Network[.]framework|CFNetwork|socket[(]|connect[(]' "$experiment_dir/Sources/main.swift" >/dev/null; then
    print -u2 -- "Swift gate source contains a network API reference"
    exit 13
fi

python_pid_file="$temporary_root/python.pid"
gate_stdout="$temporary_root/gate.stdout"
gate_stderr="$temporary_root/gate.stderr"
STAGE6_PYTHON_PID_FILE="$python_pid_file" "$swift_executable" >"$gate_stdout" 2>"$gate_stderr" &
swift_pid=$!

for _attempt in {1..100}; do
    [[ -s "$python_pid_file" ]] && break
    /bin/sleep 0.05
done
if [[ ! -s "$python_pid_file" ]]; then
    print -u2 -- "Python PID was not published"
    wait "$swift_pid" || true
    exit 14
fi
python_pid="$(<"$python_pid_file")"

for observation in {1..5}; do
    observation_file="$temporary_root/lsof-$observation.txt"
    set +e
    /usr/sbin/lsof -nP -a -p "$swift_pid,$python_pid" -i >"$observation_file" 2>/dev/null
    lsof_status=$?
    set -e
    if [[ $lsof_status -eq 0 ]]; then
        print -u2 -- "Internet socket observed for Stage 6 process"
        wait "$swift_pid" || true
        exit 15
    fi
    if [[ $lsof_status -ne 1 ]]; then
        print -u2 -- "lsof observation failed: status=$lsof_status"
        wait "$swift_pid" || true
        exit 16
    fi
    /bin/sleep 0.4
done

set +e
wait "$swift_pid"
gate_status=$?
set -e
if [[ $gate_status -ne 0 ]]; then
    print -u2 -- "Stage 6 probe failed: status=$gate_status"
    /bin/cat "$gate_stderr" >&2
    exit 17
fi
if [[ -s "$gate_stderr" ]]; then
    print -u2 -- "Stage 6 probe wrote unexpected outer stderr"
    exit 18
fi
/bin/cat "$gate_stdout"
