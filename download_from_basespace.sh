#!/bin/bash

# Set default values for arguments
tarfile_path="$(pwd)"
fastq_path="$(pwd)"
bs_config="default"

# Parse command-line arguments
eval set -- "$(
  getopt --options=r:p:t:f:c: \
         --longoptions=run-ids:,project-ids:,tarfile-path:,fastq-path:,config: \
         --name "$0" -- "$@"
)"

while true
do
  case "$1" in
    -r|--run-ids)
      IFS="," read -a run_ids < <(echo "$2")
      shift 2 ;;
    -p|--project-ids)
      IFS="," read -a project_ids < <(echo "$2")
      shift 2 ;;
    -t|--tarfile-path)
      tarfile_path="$(readlink --canonicalize "$2")"
      shift 2 ;;
    -f|--fastq-path)
      fastq_path="$(readlink --canonicalize "$2")"
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

if [[ ${run_ids} == "" ]]
then
  echo    "Usage:"
  echo -n "  bash download_from_basespace.sh [options] "
  echo -n "-r|--run-ids [RunID1,RunID2,...] "
  echo    "-p|--project-ids [ProjectID1,ProjectID2,...]"
  echo    "Options:"
  echo -n "  -r, --run-ids        "
  echo    "Comma-separated list of BaseSpace Run IDs (integers)"
  echo -n "  -p, --project-ids    "
  echo    "Comma-separated list of BaseSpace Project IDs (integers)"
  echo -n "  -t, --tarfile-path   "
  echo    "Path where a tarball of Run files will be written"
  echo    "                       (Default: current working directory)"
  echo -n "  -f, --fastq-path     "
  echo    "Path where directories of FASTQ files will be written"
  echo    "                       (Default: current working directory)"
  echo    "  -c, --config         BaseSpace CLI configuration"
  echo    "                       (Default: 'default')"
else
  script_path="$(readlink --canonicalize "$(dirname "${0}")")"

  # Define paths
  tempdir=$(mktemp --directory)

  # Declare variables
  declare -a seq_run_paths

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
    for run_id in ${run_ids[@]}
    do
      # Change IFS temporarily (note lack of semicolon after assignment) to ","
      # and read info pertaining to Run ID into an array
      # (Name, Id, ExperimentName, Status)
      IFS="," read -a run_info < <(
        bs --config=${bs_config} list runs --format=csv \
           --filter-field=Id --filter-term=${run_id} | tail -n 1
      )

      # Retrieve tarball of Run metadata
      bash "${script_path}/download_basespace_run_metadata.sh" \
           --id=${run_id} --output-path="${tarfile_path}" --config=${bs_config}

      # Construct sequencing-run-specific path and add to array
      seq_run_path="${fastq_path}/${run_info[0]}"
      seq_run_paths+=("${seq_run_path}")
      # If it exists, remove it first; then, create it (user-readable only)
      if [[ -e "${seq_run_path}" ]]
      then
        chmod -R u+w "${seq_run_path}"/
        rm -rf "${seq_run_path:?}"/
      fi
      mkdir --verbose --mode=2700 "${seq_run_path}"/
    done

    for project_id in ${project_ids[@]}
    do
      # Retrieve Project files to temporary directory containing a 
      # directory tree named with project ID and sample IDs, e.g.,
      #   tempdir/SampleName1_SampleId1/*.fastq.gz
      #   tempdir/SampleName2_SampleId2/*.fastq.gz
      #   ...
      #   tempdir/SampleNameN_SampleIdN/*.fastq.gz
      # Note: this directory tree is also read-only and will need to be unlocked
      #       before the cleanup step below.
      bash "${script_path}/download_basespace_project.sh" \
           --id=${project_id} --output-path=${tempdir} --config=${bs_config}
      # Reset downloaded files/folders to user-writable to facilitate cleanup
      chmod -R u+w ${tempdir}/

      # Iterate over each FASTQ file retrieved
      for filename in ${tempdir}/*/*.fastq.gz
      do
        # Test integrity of gzip archive; print message and terminate if corrupt
        if [[ $(gzip -t ${filename}) ]]
        then
          echo "${filename} is corrupted!  Terminating."
          exit
        else
          echo "${filename} is OK."
        fi
        # Extract the flowcell from the first read of the file
        flowcell="$(zcat ${filename} | head -n 1 | cut -f3 -d':')"
        # Determine if sequencing run directory exists
        # with name ending in flowcell ID
        seq_run_path="$(ls -d "${fastq_path}"/*${flowcell} 2> /dev/null)"
        # If not, create one named solely with flowcell ID, and add to array
        if [[ ${seq_run_path} == "" ]]
        then
          seq_run_path="${fastq_path}/${flowcell}"
          mkdir --verbose --mode=2700 "${seq_run_path}"/
          seq_run_paths+=("${seq_run_path}")
        fi
        # Concatenate lane-specific FASTQ files to sample-specific FASTQ files
        # within the sequencing run folder corresponding to the flowcell
        destination_filename="${seq_run_path}/$(basename ${filename/_L00?_/_})"
        echo "Appending ${filename} to ${destination_filename}"
        cat ${filename} >> "${destination_filename}"
      done
      # Clean up temp folder
      rm -rf ${tempdir:?}/*
    done

    # Set sequencing-run-specific directories to group-readable and read-only
    echo "Setting FASTQ directories to read-only."
    for seq_run_path in "${seq_run_paths[@]}"
    do
      chmod -Rc ug+rX,ug-w,o-rwx "${seq_run_path}"
    done

    # Clean up
    rm -rf ${tempdir:?}/
  fi
fi
