#!/bin/bash

# Set default values for arguments
output_path="$(pwd)"
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
      project_id="$2"
      shift 2 ;;
    -o|--output-path)
      output_path="$(readlink --canonicalize "$2")"
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

if [[ ${project_id} == "" ]]
then
  echo "Usage:"
  echo "  bash download_basespace_project.sh [options] -i|--id [Project ID]"
  echo "Options:"
  echo "  -i, --id             BaseSpace Project ID (integer)"
  echo "  -o, --output-path    Path where the FASTQ files will be written"
  echo "                       (Default: current working directory)"
  echo "  -c, --config         BaseSpace CLI configuration"
  echo "                       (Default: 'default')"
else
  # Load and list modules
  module load basespace-cli
  module list

  # Get BaseSpace CLI version
  bscli_version="$(bs --version | tr -s " " "\n" | grep -E -o "^[0-9\.]+$")"
  # Check whether the basespace-cli is a deprecated Python-based version
  # (versions 0.5.1-284 through basespace-cli-0.8.12-590);
  # if so, exit with an error message, and if not, proceed
  if [[ ${bscli_version} > "0.5" && ${bscli_version} < "0.9" ]]
  then
    echo "BaseSpace version ${bscli_version} is no longer supported."
  else
    # Change IFS temporarily (note lack of semicolon after assignment) to ","
    # and read info pertaining to Project ID into an array
    # (Name, Id, TotalSize)
    IFS="," read -a project_info < <(
      bs --config=${bs_config} list projects --format=csv \
         --filter-field=Id --filter-term=${project_id} | tail -n 1
    )

    # Retrieve all files from Project to destination path
    echo -n "Retrieving files from BaseSpace Project "
    echo -n "${project_id} ('${project_info[0]}') "
    echo "to ${output_path}/"
    bs --config=${bs_config} --verbose download project \
       --id=${project_id} --output="${output_path}"

    # Change permissions to read-only
    chmod -R ug+rX,ug-w,o-rwx "${output_path}"/
  fi
fi
