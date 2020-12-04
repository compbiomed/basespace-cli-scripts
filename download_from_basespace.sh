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

if [[ ${#run_ids[@]} -eq 0 && ${#project_ids[@]} -eq 0 ]]
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
  declare -A run_names
  declare -a flowcell_paths

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
      # Extract flowcell ID from run name
      run_name=${run_info[0]}
      flowcell=${run_name:(-9)}
      # Add run name to associative array, labeled with flowcell ID
      run_names[${flowcell}]=${run_name}

      # Retrieve tarball of Run metadata
      bash "${script_path}/download_basespace_run_metadata.sh" \
           --id=${run_id} --output-path="${tarfile_path}" --config=${bs_config}
    done

    for project_id in ${project_ids[@]}
    do
      # Retrieve Project files to temporary directory tree 
      # named with sample names and download session IDs, e.g.,
      #   tempdir/SampleName1_L001_ds.DownloadSessionId1/*.fastq.gz
      #   tempdir/SampleName1_L002_ds.DownloadSessionId2/*.fastq.gz
      #   tempdir/SampleName2_L001_ds.DownloadSessionId3/*.fastq.gz
      #   tempdir/SampleName2_L002_ds.DownloadSessionId4/*.fastq.gz
      #   ...
      # where DownloadSessionId is a 32-character hex string that is unique
      # to a specific download session (files from a sample/lane combination).
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
        if gzip -t ${filename}
        then
          echo "${filename} is OK."
        else
          echo "${filename} is corrupted!  Terminating."
          exit
        fi

        # Extract the flowcell from the first read of the file
        flowcell="$(zcat ${filename} | head -n 1 | cut -f3 -d':')"
        # Construct path where FASTQ files will be written for given flowcell ID
        if [[ ${run_names[${flowcell}]} != "" ]]
        then
          # If Run exists with name ending in flowcell ID, use that as label
          flowcell_path="${fastq_path}/${run_names[${flowcell}]}"
        else
          # Otherwise, use the flowcell ID itself as the label
          flowcell_path="${fastq_path}/${flowcell}"
        fi
        # If flowcell-specific path does not exist, create and add to array
        if [[ ! -d "${flowcell_path}" ]]
        then
          mkdir --verbose --mode=2700 "${flowcell_path}"/
          flowcell_paths+=("${flowcell_path}")
        fi

        # Concatenate lane-specific FASTQ files to sample-specific FASTQ files
        # within the sequencing run folder corresponding to the flowcell
        # Note: the destination filename is constructed in two steps below
        #       to replace only the "L00?" lane ID glob in the base filename
        #       and not the one in the name of the temporary directory
        destination_filename="$(basename ${filename})"
        destination_filename="${flowcell_path}/${destination_filename/_L00?_/_}"
        echo "Appending ${filename} to ${destination_filename}"
        cat ${filename} >> "${destination_filename}"
      done
      # Clean up temp folder
      rm -rf ${tempdir:?}/*
    done

    # Set sequencing-run-specific directories to group-readable and read-only
    echo "Setting FASTQ directories to read-only."
    for flowcell_path in "${flowcell_paths[@]}"
    do
      chmod -Rc ug+rX,ug-w,o-rwx "${flowcell_path}"
    done

    # Clean up
    rm -rf ${tempdir:?}/
  fi
fi
