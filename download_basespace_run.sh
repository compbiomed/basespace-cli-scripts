#!/bin/bash

# Set default values for arguments
output_path="$(pwd)"
bs_config="default"
exclude_extensions=(jpg)

# Parse command-line arguments
eval set -- "$(
  getopt --options=i:o:c:e: \
         --longoptions=id:,output-path:,config:,exclude: \
         --name "$0" -- "$@"
)"

while true
do
  case "$1" in
    -i|--id)
      run_id="$2"
      shift 2 ;;
    -o|--output-path)
      output_path="$(readlink --canonicalize "$2")"
      shift 2 ;;
    -c|--config)
      bs_config="$2"
      shift 2 ;;
    -e|--exclude)
      IFS="," read -a exclude_extensions < <(echo "$2")
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
  echo "  bash download_basespace_run.sh [options] -i|--id [Run ID]"
  echo "Options:"
  echo "  -i, --id             BaseSpace Run ID (integer)"
  echo "  -o, --output-path    Path where the Run files will be written"
  echo "                       (Default: current working directory)"
  echo "  -c, --config         BaseSpace CLI configuration"
  echo "                       (Default: 'default')"
  echo "  -e, --exclude        Comma-separated list of extensions to exclude"
  echo "                       (Default: 'jpg')"
else
  # All file extensions present within a given Run
  extensions=(bci bgzf bin filter jpg json locs tsv txt xml zip)

  # Remove excluded extensions
  readarray -t extensions < <(
    printf "%s\n" "${extensions[@]}" "${exclude_extensions[@]}" | sort | uniq -u
  )

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
    # Change IFS temporarily (note lack of semicolon after assignment) to ","
    # and read info pertaining to Run ID into an array
    # (Name, Id, ExperimentName, Status)
    IFS="," read -a run_info < <(
      bs --config=${bs_config} list runs --format=csv \
         --filter-field=Id --filter-term=${run_id} | tail -n 1
    )
    # Retrieve all files from Run (except for specified extensions)
    # to destination path
    echo -n "Retrieving files from BaseSpace Run "
    echo -n "${run_id} ('${run_info[0]}'), Experiment '${run_info[2]}' "
    echo "to ${output_path}/"
    echo "Retrieving only files with the following extensions: ${extensions[*]}"
    bs --config=${bs_config} --verbose download run \
       --id=${run_id} --output="${output_path}" \
       --extension="$(IFS=","; echo "${extensions[*]}")"

    # Change permissions to read-only
    chmod -R ug+rX,ug-w,o-rwx "${output_path}"/
  fi
fi
