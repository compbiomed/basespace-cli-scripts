#!/bin/bash

# Set default values for arguments
tarfile_path="$(pwd)"
bs_config="default"

# Parse command-line arguments
eval set -- "$(
  getopt --options=i:o:c: \
         --longoptions=id:,output-path:,config: \
         --name "$0" -- "$@"
)"

while true
do
  case "$1" in
    -i|--id)
      run_id="$2"
      shift 2 ;;
    -o|--output-path)
      tarfile_path="$(readlink --canonicalize "$2")"
      shift 2 ;;
    -c|--config)
      bs_config="$2"
      shift 2 ;;
    --)
      shift
      break ;;
    *)
      echo "Internal error"
      exit 1 ;;
  esac
done

if [[ ${run_id} == "" ]]
then
  echo "Usage:"
  echo "  bash download_basespace_run_metadata.sh [options] -i|--id [Run ID]"
  echo "Options:"
  echo "  -i, --id             BaseSpace Run ID (integer)"
  echo "  -o, --output-path    Path where a tar file will be written"
  echo "                       (Default: current working directory)"
  echo "  -c, --config         BaseSpace CLI configuration"
  echo "                       (Default: 'default')"
else
  # Note: this script assumes that other scripts are in the same path
  script_path="$(readlink --canonicalize "$(dirname "${0}")")"

  # All file extensions to exclude from Run download
  exclude_extensions=(bci bgzf filter jpg locs)

  # Make temporary directory and navigate to it
  tempdir="$(mktemp --directory)"
  cd ${tempdir}/ || exit

  # Retrieve Run files to temporary directory,
  # excluding basecalls, locations/control/filter files, and thumbnails
  bash "${script_path}/download_basespace_run.sh" \
       --id=${run_id} --output-path="$(pwd)" --config=${bs_config} \
       --exclude=$(IFS=,; echo "${exclude_extensions[*]}")

  # Extract run name from RunInfo.xml
  run_regex="[0-9]{6}_[^_]+_[0-9]+_[AB]?[A-Za-z0-9]{9}"
  run_name="$(grep -E -o "${run_regex}" ${tempdir}/RunInfo.xml)"

  # Check for empty run name (in case RunInfo.xml is missing or corrupt,
  # or if this script is prematurely terminated)
  if [[ ${run_name} != "" ]]
  then
    # Construct tar filename
    tar_filename="${tarfile_path}/${run_name}.tar.gz"
    # Remove the tarball if it exists
    # (i.e., if this script is being re-run to complete an interrupted download)
    rm -fv "${tar_filename}"
    # Create tarball
    echo "Archiving Run files to: ${tar_filename}"
    tar czvf "${tar_filename}" \
        --mode=ug-w,ug+rX,o-rwx --owner=root --group=root *
    # Make the tarball read-only
    chmod ug+r,ug-wx,o-rwx "${tar_filename}"
  fi

  # Clean up
  cd ../
  chmod u+w -R ${tempdir}/
  rm -rf ${tempdir:?}/
fi
