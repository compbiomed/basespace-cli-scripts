#!/bin/bash
# Download files from BaseSpace Run to SCC
# Adam Gower
#
# INPUT
# This script expects the following command-line arguments:
#   1. The BaseSpace Run ID (integer)
#   2. The path where the Run files will be written
#   3. The BaseSpace configuration to use
#   4. [optional] Any globs to exclude from download; defaults to '*.jpg'
#
# OUTPUT
# The script places the Run files in the specified path.

if [[ $# -lt 3 ]]
then
  echo -n "Usage: bash download_basespace_run.sh "
  echo -n "[BaseSpace Run ID] [destination path] [basespace-cli config] "
  echo    "[globs to exclude]"
  echo    "       [globs to exclude] default: '*.jpg'"
else
  # Parse command-line arguments
  arglist=("$@")
  run_id="${arglist[0]}"
  destination_path="$(readlink --canonicalize "${arglist[1]}")"
  bs_config="${arglist[2]}"
  exclude_globs=(${arglist[@]:3})

  # If no globs were provided, use "*.jpg" as the default
  if [[ ${#exclude_globs[@]} == 0 ]]
  then
    exclude_globs=("*.jpg")
  fi

  # Load and list modules
  module load basespace-cli/0.8.12.590
  module list

  # Get info pertaining to Run ID
  run_info="$(bs -c ${bs_config} list runs -f csv --quote none)"
  run_info="$(echo "${run_info}" | grep "${run_id}")"
  run_name="$(echo "${run_info}" | cut -f2 -d',')"
  experiment_name="$(echo "${run_info}" | cut -f3 -d',')"

  # Get all files from Run, except for jpg thumbnail images
  echo -n "Retrieving files from BaseSpace Run "
  echo    "${run_id} ('${experiment_name}') to ${destination_path}/"
  bs cp //~${bs_config}/Runs/${run_id}/** \
     $(printf -- "--exclude %s " ${exclude_globs[@]}) ${destination_path}

  # Change permissions to read-only
  chmod -R ug+rX,ug-w,o-rwx ${destination_path}/
fi
