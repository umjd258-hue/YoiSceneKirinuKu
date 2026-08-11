#!/bin/zsh

set -euo pipefail

readonly expected_installer_sha256="8e58affb218c155a1dfdc27b291f817129669f8760e7a297adb2e4439ba5d2e8"
readonly installer_path="${SRCROOT}/vendor/python/3.13.14/python-3.13.14-macos11.pkg"
readonly manifest_path="${SRCROOT}/vendor/python/3.13.14/SHA256SUMS"
readonly destination="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/Python.framework"

if [[ ! -f "${installer_path}" || ! -s "${installer_path}" ]]; then
    print -u2 "Stage 6 Python installer is missing. Fetch the Git LFS object before building."
    exit 1
fi

if [[ ! -f "${manifest_path}" ]]; then
    print -u2 "Stage 6 Python SHA256SUMS is missing."
    exit 1
fi

readonly actual_installer_sha256="$(/usr/bin/shasum -a 256 "${installer_path}" | /usr/bin/awk '{print $1}')"
if [[ "${actual_installer_sha256}" != "${expected_installer_sha256}" ]]; then
    print -u2 "Stage 6 Python installer SHA-256 mismatch."
    exit 1
fi

if ! /usr/bin/grep -Fqx "${expected_installer_sha256}  python-3.13.14-macos11.pkg" "${manifest_path}"; then
    print -u2 "Stage 6 Python SHA256SUMS does not contain the fixed installer digest."
    exit 1
fi

readonly work_root="$(/usr/bin/mktemp -d "${DERIVED_FILE_DIR}/Stage6PythonRuntime.XXXXXX")"
trap '/bin/rm -rf -- "${work_root}"' EXIT

readonly expanded_root="${work_root}/expanded"
readonly source_root="${expanded_root}/Python_Framework.pkg/Payload/Versions/3.13"
readonly runtime_framework="${work_root}/Python.framework"
readonly runtime_version="${runtime_framework}/Versions/3.13"

/usr/sbin/pkgutil --expand-full "${installer_path}" "${expanded_root}"

for required_path in \
    "${source_root}/bin/python3.13" \
    "${source_root}/Python" \
    "${source_root}/Resources/Info.plist" \
    "${source_root}/Resources/Python.app/Contents/MacOS/Python" \
    "${source_root}/Resources/Python.app/Contents/Info.plist" \
    "${source_root}/lib/python3.13"
do
    if [[ ! -e "${required_path}" ]]; then
        print -u2 "Required Stage 6 Python runtime input is missing: ${required_path}"
        exit 1
    fi
done

/bin/mkdir -p "${runtime_version}/bin"
/bin/mkdir -p "${runtime_version}/lib/python3.13"
/bin/mkdir -p "${runtime_version}/Resources/Python.app/Contents/MacOS"

/bin/cp "${source_root}/bin/python3.13" "${runtime_version}/bin/python3.13"
/bin/cp "${source_root}/Python" "${runtime_version}/Python"
/bin/cp "${source_root}/Resources/Info.plist" "${runtime_version}/Resources/Info.plist"
/bin/cp "${source_root}/Resources/Python.app/Contents/MacOS/Python" "${runtime_version}/Resources/Python.app/Contents/MacOS/Python"
/bin/cp "${source_root}/Resources/Python.app/Contents/Info.plist" "${runtime_version}/Resources/Python.app/Contents/Info.plist"
/usr/bin/ditto "${source_root}/lib/python3.13" "${runtime_version}/lib/python3.13"

/bin/rm -rf -- "${runtime_version}/lib/python3.13/site-packages"
/bin/rm -rf -- "${runtime_version}/lib/python3.13/ensurepip"

readonly excluded_wheels=(
    "${runtime_version}/lib/python3.13/test/wheeldata/setuptools-79.0.1-py3-none-any.whl"
    "${runtime_version}/lib/python3.13/test/test_importlib/metadata/data/example2-1.0.0-py3-none-any.whl"
    "${runtime_version}/lib/python3.13/test/test_importlib/metadata/data/example-21.12-py3-none-any.whl"
)
for excluded_wheel in "${excluded_wheels[@]}"; do
    if [[ -e "${excluded_wheel}" ]]; then
        /bin/unlink "${excluded_wheel}"
    fi
done

/bin/ln -s 3.13 "${runtime_framework}/Versions/Current"
/bin/ln -s Versions/Current/Python "${runtime_framework}/Python"
/bin/ln -s Versions/Current/Resources "${runtime_framework}/Resources"

/bin/chmod u+x "${runtime_version}/bin/python3.13"
/bin/chmod u+x "${runtime_version}/Python"
/bin/chmod u+x "${runtime_version}/Resources/Python.app/Contents/MacOS/Python"

/usr/bin/install_name_tool -change \
    /Library/Frameworks/Python.framework/Versions/3.13/Python \
    @executable_path/../Python \
    "${runtime_version}/bin/python3.13"
/usr/bin/install_name_tool -change \
    /Library/Frameworks/Python.framework/Versions/3.13/Python \
    @executable_path/../../../../Python \
    "${runtime_version}/Resources/Python.app/Contents/MacOS/Python"
/usr/bin/install_name_tool -id \
    @rpath/Python.framework/Versions/3.13/Python \
    "${runtime_version}/Python"

/usr/bin/codesign --force --sign - "${runtime_version}/Python"
/usr/bin/codesign --force --sign - "${runtime_version}/bin/python3.13"
/usr/bin/codesign --force --sign - "${runtime_version}/Resources/Python.app/Contents/MacOS/Python"
/usr/bin/codesign --force --sign - "${runtime_version}/Resources/Python.app"
/usr/bin/codesign --force --sign - "${runtime_framework}"
/usr/bin/codesign --verify --strict --deep "${runtime_framework}"

/bin/mkdir -p "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
/bin/rm -rf -- "${destination}"
/usr/bin/ditto "${runtime_framework}" "${destination}"
/usr/bin/codesign --verify --strict --deep "${destination}"
"${destination}/Versions/3.13/bin/python3.13" -I -S --version | /usr/bin/grep -Fqx "Python 3.13.14"
