#!/bin/bash
# Download FASTQ files from BaseSpace Project to SCC
# Adam Gower
#
# INPUT
# This script expects the following command-line arguments:
#   1. The BaseSpace Project ID (integer)
#   2. The path where the FASTQ files will be written
#   3. The BaseSpace configuration to use
#
# OUTPUT
# The script places the Project files in the specified path.

if [[ $# -ne 3 ]]
then
  echo -n "Usage: bash download_basespace_project.sh "
  echo    "[BaseSpace Project ID] [destination path] [basespace-cli config]"
else
  # Parse command-line arguments
  project_id="${1}"
  destination_path="$(readlink --canonicalize "${2}")"
  bs_config="${3}"

  # Load and list modules
  module load basespace-cli/0.8.12.590
  module list

  # Get info pertaining to Project ID
  project_info="$(bs -c ${bs_config} list projects -f csv --quote none)"
  project_name="$(
    echo "${project_info}" | grep "${project_id}" | cut -f2 -d','
  )"

  # Retrieve all files from Project to destination path
  echo -n "Retrieving files from BaseSpace Project "
  echo    "${project_id} ('${project_name}') to ${destination_path}/"
  bs cp //~${bs_config}/Projects/${project_id}/Samples/:* ${destination_path}

  # Change permissions to read-only
  chmod -R ug+rX,ug-w,o-rwx ${destination_path}/
fi
