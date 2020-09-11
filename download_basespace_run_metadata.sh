#!/bin/bash
# Download metadata files from BaseSpace Run to a tarfile
# Adam Gower
#
# INPUT
# This script expects the following command-line arguments:
#   1. The BaseSpace Run ID (integer)
#   2. The path where a tarfile of Run files will be written
#   3. The BaseSpace configuration to use
#
# OUTPUT
# This script produces the following tarball:
#   {tarfile path}/{Run name}.tar.gz
#   which contains any Run files that do not match:
#   *.jpg, *.bcl.gz, *.bgzf, *.bci, *.filter, *.control, *.*locs

if [[ $# -ne 3 ]]
then
  echo -n "Usage: bash download_basespace_run_metadata.sh "
  echo    "[BaseSpace Run ID] [tarfile path] [basespace-cli config]"
else
  # Parse command-line arguments
  script_path="$(readlink --canonicalize "$(dirname $0)")"
  run_id="$1"
  tarfile_path="$(readlink --canonicalize "$2")"
  bs_config="$3"

  # Make temp directory and navigate to it
  tempdir="$(mktemp --directory)"
  cd $tempdir/

  # Retrieve Run files to it,
  # excluding thumbnails, basecalls, filters, and locations (coordinates)
  bash "$script_path/download_basespace_run.sh" $run_id . $bs_config \
       "*.jpg" "*.bcl.gz" "*.bgzf" "*.bci" "*.filter" "*.control" "*.*locs"

  # Extract run name from RunInfo.xml
  run_regex="[0-9]+_[^_]+_[0-9]+_[AB][A-Za-z0-9]{9}"
  run_name="$(egrep -o $run_regex $tempdir/RunInfo.xml)"

  # Check for empty run name
  # (in case RunInfo.xml is missing or corrupt,
  # or if this script is prematurely terminated)
  if [[ ${run_name} != "" ]]
  then
    # Construct tar filename
    tar_filename="$tarfile_path/${run_name}.tar.gz"
    # Remove the tarball if it exists
    # (i.e., if this script is being re-run to complete an interrupted download)
    rm -fv $tar_filename
    # Create tarball
    echo "Archiving Run files to $tar_filename"
    tar czvf $tar_filename --mode=ug-w,ug+rX,o-rwx --owner=root --group=root *
    # Make the tarball read-only
    chmod ug+r,ug-wx,o-rwx $tar_filename
  fi

  # Clean up
  cd ../
  chmod u+w -R $tempdir/
  rm -rf $tempdir/
fi
