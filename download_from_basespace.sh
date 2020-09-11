#!/bin/bash
# Download files from BaseSpace Run and Project to SCC
# Adam Gower
#
# INPUT
# This script expects the following command-line arguments:
#   1. A comma-separated list of BaseSpace Run IDs (integers)
#   2. A comma-separated list of BaseSpace Project IDs (integers)
#   3. The path where tarballs of Run files will be written
#   4. The SCC project account associated with the files
#   5. The BaseSpace configuration to use
#
# OUTPUT
# This script performs the following tasks:
# 1. Produces the following tarballs:
#    [tarfile path]/[run_name].tar.gz
#      where run_name = [yymmdd]_[instrument]_[run index]_[A or B][flowcell]
#    Each tarball contains any Run files that do not match:
#      *.jpg, *.bcl.gz, *.bgzf, *.bci, *.filter, *.control, *.*locs
# 2. Creates the following directory for each Run:
#      /restricted/projectnb/[SCC project account]/fastq/[run_name]/
# 3. Downloads .fastq.gz files for each BaseSpace Project to temp directories
# 4. Tests the .fastq.gz files for integrity using 'gzip -t'
# 5. Concatenates .fastq.gz files for each sample across all lanes to a
#    .fastq.gz file in the Run-specific directory that matches the flowcell ID
#    e.g., SampleX_S1_L001_R1_001.fastq.gz >> 
#          /.../fastq/[run_name]/SampleX_S1_R1_001.fastq.gz

if [[ $# -ne 5 ]]
then
  echo -n "Usage: bash download_from_basespace.sh "
  echo -n "[BaseSpaceRunID1,BaseSpaceRunID2,...] "
  echo -n "[BaseSpaceProjectID1,BaseSpaceProjectID2,...] "
  echo    "[tarfile path] [SCC project account] [basespace-cli config]"
else
  script_path="$(readlink --canonicalize "$(dirname ${0})")"
  # Parse comma-separated lists into arrays
  run_ids=($(echo "${1}" | tr ',' ' '))
  project_ids=($(echo "${2}" | tr ',' ' '))
  tarfile_path="$(readlink --canonicalize "${3}")"
  scc_project="${4}"
  bs_config="${5}"

  # Define paths
  fastq_path="/restricted/projectnb/${scc_project}/fastq"
  tempdir=$(mktemp --directory)

  # Declare variables
  declare -a seq_run_paths

  # Load and list modules
  module load basespace-cli/0.8.12.590
  module list

  # Look up Run info using BaseSpace CLI
  run_info="$(bs -c ${bs_config} list runs -f csv --quote none)"

  for run_id in ${run_ids[@]}
  do
    # Extract Run name from BaseSpace CLI output
    run_name="$(echo "${run_info}" | grep "${run_id}" | cut -f2 -d',')"

    # Retrieve tarball of Run metadata
    bash "${script_path}/download_basespace_run_metadata.sh" \
         ${run_id} ${tarfile_path} ${bs_config}

    # Construct sequencing-run-specific path and add to array
    seq_run_path="${fastq_path}/${run_name}"
    seq_run_paths+=(${seq_run_path})
    # If it exists, remove it first; then, create it
    if [[ -e ${seq_run_path} ]]
    then
      chmod -R u+w ${seq_run_path}/
      rm -rf ${seq_run_path}/
    fi
    mkdir --verbose --mode=2700 ${seq_run_path}/
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
         ${project_id} ${tempdir} ${bs_config}
    # Reset downloaded files/folders to user-writable to facilitate cleanup
    chmod -R u+w ${tempdir}/

    # Iterate over each FASTQ file retrieved
    for filename in ${tempdir}/*/*.fastq.gz
    do
      # Test integrity of gzip archive
      gzip -t ${filename}
      # Print a message and terminate if the file is corrupt
      if [[ $? -eq 0 ]]
      then
        echo "${filename} is OK."
      else
        echo "${filename} is corrupted!  Terminating."
        exit
      fi
      # Extract the flowcell from the first read of the file
      flowcell="$(zcat ${filename} | head -n 1 | cut -f3 -d':')"
      # Determine if sequencing run directory exists
      # with name ending in flowcell ID
      seq_run_path="$(ls -d ${fastq_path}/*${flowcell} 2> /dev/null)"
      # If not, create one named solely with flowcell ID, and add to array
      if [[ $? -ne 0 ]]
      then
        seq_run_path="${fastq_path}/${flowcell}"
        mkdir --verbose --mode=2700 ${seq_run_path}/
        seq_run_paths+=(${seq_run_path})
      fi
      # Concatenate lane-specific FASTQ files to sample-specific FASTQ files
      # within the sequencing run folder corresponding to the flowcell
      destination_filename="${seq_run_path}/$(basename ${filename/_L00?_/_})"
      echo "Appending ${filename} to ${destination_filename}"
      cat ${filename} >> ${destination_filename}
    done
    # Clean up temp folder
    rm -rf ${tempdir}/*
  done

  # Set sequencing-run-specific directories to group-readable and read-only
  echo "Setting FASTQ directories to read-only."
  for seq_run_path in ${seq_run_paths[@]}
  do
    chmod -Rc ug+rX,ug-w,o-rwx "${seq_run_path}"
  done

  # Clean up
  rm -rf ${tempdir}/
fi
