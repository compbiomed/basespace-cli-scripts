#!/bin/bash

# Set default values for arguments
bcl2fastq_path="$(pwd)"
bs_config="default"

# Parse command-line arguments
eval set -- "$(
  getopt --options=b:c: \
         --longoptions=bcl2fastq-path:,config: \
         --name "$0" -- "$@"
)"

while true
do
  case "$1" in
    -b|--bcl2fastq-path)
      bcl2fastq_path="$(readlink --canonicalize "$2")"
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

if [[ ${bcl2fastq_path} == "" ]]
then
  echo "Usage:"
  echo "  bash upload_basespace_bcl2fastq.sh [options]"
  echo "Options:"
  echo "  -b, --bcl2fastq-path     Path containing bcl2fastq output"
  echo "                           (Default: current working directory)"
  echo "  -c, --config             BaseSpace CLI configuration"
  echo "                           (Default: 'default')"
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
    # Exit with an error message if an old Python version is installed
    echo "BaseSpace version ${bscli_version} is no longer supported."
  else
    # Get array of FASTQ filenames
    readarray -t fastq_filenames < \
      <(find "${bcl2fastq_path}" -name "*.fastq.gz")
    # Remove filenames to get paths to unique project folders
    readarray -t project_paths < \
      <(printf "%q\n" "${fastq_filenames[@]}" | xargs -I{} dirname {} | sort -u)
    # Iterate over each project folder
    for project_path in "${project_paths[@]}"
    do
      # Create Project and capture ID from output
      project_name="$(basename "${project_path}")"
      echo "Creating Project: ${project_name}"
      project_id=$(
        bs --config=${bs_config} create project \
           --name="${project_name}" --terse
      )
      # Upload FASTQ files to new Project
      bs --config=${bs_config} --verbose upload dataset \
         --project=${project_id} --recursive "${project_path}"/
    done
  fi
fi
